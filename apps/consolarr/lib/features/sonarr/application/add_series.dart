// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// Preference name of the remembered root folder (per server).
const addRootFolderPref = 'add.rootFolder';

/// What the add options form offers.
class AddFormData {
  const AddFormData({
    required this.profiles,
    required this.rootFolders,
    required this.tags,
    this.rememberedRootFolder,
    this.tagsFailed = false,
  });

  final List<ArrQualityProfile> profiles;
  final List<ArrRootFolder> rootFolders;
  final List<ArrTag> tags;

  /// The tag list could not be read (tags are optional, so the form still
  /// works; it says so and offers a retry instead of showing "no tags").
  final bool tagsFailed;

  /// Root folder path used last time on this server, when it still exists.
  final String? rememberedRootFolder;

  /// The folder to preselect: the remembered one, else the first.
  ArrRootFolder? get defaultRootFolder {
    for (final f in rootFolders) {
      if (f.path == rememberedRootFolder) return f;
    }
    return rootFolders.isEmpty ? null : rootFolders.first;
  }

  /// Adding is impossible without a profile and a root folder.
  bool get isUsable => profiles.isNotEmpty && rootFolders.isNotEmpty;
}

/// Profiles, root folders and tags for the options sheet. Fails with the
/// [AppError] of the first failed required list; tags are optional.
final addFormDataProvider = FutureProvider.autoDispose<AddFormData>(
  retry: (_, _) => null,
  (ref) async {
    final session = await ref.watch(sonarrSessionProvider.future);
    if (session == null) throw const AppError(ErrorCategory.notFound);
    final results = await (
      session.api.qualityProfiles(),
      session.api.rootFolders(),
      session.api.tags(),
    ).wait;
    final profiles = results.$1.when(ok: (v) => v, err: (e) => throw e);
    final folders = results.$2.when(ok: (v) => v, err: (e) => throw e);
    String? remembered;
    try {
      remembered = await ref
          .read(sonarrPrefsStoreProvider)
          .read(session.serverId, addRootFolderPref);
    } on Object {
      remembered = null;
    }
    return AddFormData(
      profiles: profiles,
      rootFolders: folders,
      tags: results.$3.valueOrNull ?? const [],
      tagsFailed: results.$3.isErr,
      rememberedRootFolder: remembered,
    );
  },
);

/// Creates a tag on the active server (inline in the options form).
final createTagProvider = Provider<Future<Result<ArrTag>> Function(String)>(
  (ref) => (label) async {
    final session = await ref.read(sonarrSessionProvider.future);
    if (session == null) {
      return const Result.err(AppError(ErrorCategory.notFound));
    }
    return session.api.createTag(label);
  },
);

/// Reloads the library after a series was added. Override in tests.
final libraryRefreshProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(seriesLibraryProvider.notifier).refresh(),
);

/// State of one add request.
sealed class AddState {
  const AddState();
}

final class AddIdle extends AddState {
  const AddIdle();
}

final class AddSubmitting extends AddState {
  const AddSubmitting();
}

final class AddSuccess extends AddState {
  const AddSuccess(this.series, {required this.searched});

  final SonarrSeriesDetail series;

  /// "Add and search" was used.
  final bool searched;
}

final class AddFailed extends AddState {
  const AddFailed(this.error);
  final AppError error;
}

/// Adds one series. One request at a time; a failure can be retried.
final addSeriesProvider =
    NotifierProvider.autoDispose<AddSeriesNotifier, AddState>(
      AddSeriesNotifier.new,
    );

class AddSeriesNotifier extends Notifier<AddState> {
  @override
  AddState build() => const AddIdle();

  Future<void> submit(
    SonarrLookupResult lookup,
    SonarrAddOptions options,
  ) async {
    if (state is AddSubmitting || state is AddSuccess) return;
    final session = ref.read(sonarrSessionProvider).value;
    if (session == null) {
      state = const AddFailed(AppError(ErrorCategory.notFound));
      return;
    }
    state = const AddSubmitting();
    final result = await session.api.addSeries(lookup, options);
    if (!ref.mounted) return;
    final detail = result.valueOrNull;
    if (detail == null) {
      state = AddFailed(result.errorOrNull!);
      return;
    }
    ref
        .read(eventTrackerProvider)
        .track(SonarrSeriesAddedEvent(searched: options.searchForMissing));
    state = AddSuccess(detail, searched: options.searchForMissing);
    try {
      await ref
          .read(sonarrPrefsStoreProvider)
          .write(session.serverId, addRootFolderPref, options.rootFolderPath);
    } on Object {
      // The preference is a convenience only.
    }
    if (!ref.mounted) return;
    unawaited(ref.read(libraryRefreshProvider)().catchError((_) {}));
  }

  /// Back to the form after a failure.
  void reset() {
    if (state is AddFailed) state = const AddIdle();
  }
}
