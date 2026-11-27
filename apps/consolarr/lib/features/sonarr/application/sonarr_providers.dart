// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/sonarr/data/sonarr_repository.dart';
import 'package:consolarr/features/sonarr/data/view_mode_store.dart';
import 'package:consolarr/src/images/secure_image_provider.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:consolarr/features/sonarr/data/sonarr_repository.dart'
    show SeriesSnapshot;
export 'package:consolarr/features/sonarr/data/view_mode_store.dart'
    show LibraryViewMode, ViewModeStore;

/// What the series library screen shows.
sealed class LibraryState {
  const LibraryState();
}

/// No Sonarr server is configured: offer to add one.
final class LibraryNoServer extends LibraryState {
  const LibraryNoServer();
}

/// Nothing to show: the live load failed and there is no cached copy.
/// `auth_failed` is the unauthorized state (also `needs_credentials`), and
/// `unsupported_version` the SON-28 state; the screen picks copy by category.
final class LibraryFailure extends LibraryState {
  const LibraryFailure(this.error);
  final AppError error;
}

/// A list (possibly empty), live or cached.
///
/// A "partial" state (some rows unreadable) is not reachable: `arr_api`
/// parses a list all-or-nothing and reports `parse_error` for the whole
/// payload, and cached copies silently drop only damaged entries.
final class LibraryData extends LibraryState {
  const LibraryData(this.snapshot);
  final SeriesSnapshot snapshot;

  bool get isEmpty => snapshot.series.isEmpty;

  /// The live refresh failed; [snapshot] is older data.
  bool get isOffline => snapshot.offlineError != null;
}

/// The series library. Refreshing keeps the existing content visible.
final seriesLibraryProvider =
    AsyncNotifierProvider<SeriesLibraryNotifier, LibraryState>(
      SeriesLibraryNotifier.new,
    );

class SeriesLibraryNotifier extends AsyncNotifier<LibraryState> {
  SonarrRepository? _repository;

  static const _keepsContent = {
    ErrorCategory.networkUnreachable,
    ErrorCategory.timeout,
    ErrorCategory.serverError,
    ErrorCategory.notFound,
    ErrorCategory.parseError,
    ErrorCategory.responseTooLarge,
  };

  @override
  Future<LibraryState> build() async {
    _repository = null;
    final ServerConnection? connection;
    try {
      connection = await ref.watch(
        activeConnectionProvider(ServiceKind.sonarr).future,
      );
    } on AppError catch (error) {
      return LibraryFailure(error);
    }
    if (connection == null) return const LibraryNoServer();
    final repository = SonarrRepository(
      api: SonarrClient(dio: connection.dio),
      cache: ref.watch(payloadCacheProvider),
      serverId: connection.profile.id,
      clock: ref.watch(clockProvider),
    );
    _repository = repository;
    return _toState(await repository.load());
  }

  /// Reloads from the server without clearing what is on screen.
  Future<void> refresh() async {
    final repository = _repository;
    final previous = state.value;
    if (repository == null) {
      ref.invalidateSelf();
      await future;
      return;
    }
    final result = await repository.load();
    if (!ref.mounted) return;
    final error = result.errorOrNull;
    if (error != null &&
        previous is LibraryData &&
        _keepsContent.contains(error.category)) {
      state = AsyncData(LibraryData(previous.snapshot.withOfflineError(error)));
      return;
    }
    state = AsyncData(_toState(result));
  }

  LibraryState _toState(Result<SeriesSnapshot> result) =>
      result.when(ok: LibraryData.new, err: LibraryFailure.new);
}

/// Where the grid/list choice is stored.
final viewModeStoreProvider = Provider<ViewModeStore>(
  (ref) => DriftViewModeStore(ref.watch(databaseProvider)),
);

/// Grid or list (SON-01). Starts as grid, then restores the saved choice.
final viewModeProvider = NotifierProvider<ViewModeNotifier, LibraryViewMode>(
  ViewModeNotifier.new,
);

class ViewModeNotifier extends Notifier<LibraryViewMode> {
  @override
  LibraryViewMode build() {
    Future<void>.microtask(_restore);
    return LibraryViewMode.grid;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(viewModeStoreProvider).read();
      if (saved != null && ref.mounted) state = saved;
    } on Object {
      // Keep the default when storage is unavailable.
    }
  }

  Future<void> set(LibraryViewMode mode) async {
    state = mode;
    try {
      await ref.read(viewModeStoreProvider).write(mode);
    } on Object {
      // The choice still applies for this session.
    }
  }
}

/// Where series artwork comes from: the active server's secure client.
///
/// Override with a fake in tests. `null` (no server) shows placeholders.
class ArtworkSource {
  ArtworkSource({required this.dio, required SonarrApi api}) : _api = api;

  final Dio dio;
  final SonarrApi _api;

  /// The poster of [series] as an image loaded through the secure client, or
  /// null when it has none. Wrap in `ResizeImage` to decode at display size.
  ImageProvider? poster(SonarrSeries series) {
    final uri = _api.artworkUri(series, SonarrImageType.poster);
    return uri == null ? null : SecureNetworkImage(dio: dio, uri: uri);
  }
}

/// The artwork source for the active Sonarr server.
final artworkSourceProvider = Provider<ArtworkSource?>((ref) {
  final connection = ref
      .watch(activeConnectionProvider(ServiceKind.sonarr))
      .value;
  if (connection == null) return null;
  return ArtworkSource(
    dio: connection.dio,
    api: SonarrClient(dio: connection.dio),
  );
});
