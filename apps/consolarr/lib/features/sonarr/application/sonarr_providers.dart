// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/sonarr/data/sonarr_repository.dart';
import 'package:consolarr/features/sonarr/data/view_mode_store.dart';
import 'package:consolarr/shared/logging/log_events.dart';
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

/// A list (possibly empty), live or cached. [isPartial] when some rows the
/// server sent could not be read.
final class LibraryData extends LibraryState {
  const LibraryData(this.snapshot);
  final SeriesSnapshot snapshot;

  bool get isEmpty => snapshot.series.isEmpty;

  /// The live refresh failed; [snapshot] is older data.
  bool get isOffline => snapshot.offlineError != null;

  bool get isPartial => snapshot.skipped > 0;
}

/// The series library. Refreshing keeps the existing content visible. While
/// the active server changes the value is `AsyncLoading`; screens must check
/// `isLoading` and `hasError` before reading `value` (Riverpod keeps the
/// previous server's value through reloads and errors).
final seriesLibraryProvider =
    AsyncNotifierProvider<SeriesLibraryNotifier, LibraryState>(
      SeriesLibraryNotifier.new,
    );

class SeriesLibraryNotifier extends AsyncNotifier<LibraryState> {
  SonarrRepository? _repository;

  /// Rows skipped by the latest live parse (count only).
  int _skipped = 0;

  /// Bumped by every build (server switch, credential edit). Work started for
  /// an earlier build compares it after each await and drops its result.
  int _generation = 0;

  @override
  Future<LibraryState> build() async {
    _generation++;
    _repository = null;
    _skipped = 0;
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
      api: SonarrClient(
        dio: connection.dio,
        onRowsSkipped: (count) {
          _skipped = count;
          ref.read(loggerProvider).info('skipped $count malformed series rows');
        },
      ),
      cache: ref.watch(payloadCacheProvider),
      serverId: connection.profile.id,
      clock: ref.watch(clockProvider),
    );
    _repository = repository;
    return _toState(await repository.load());
  }

  /// Reloads from the server without clearing what is on screen. A result
  /// that arrives after the connection changed, or after dispose, is dropped.
  Future<void> refresh() async {
    final generation = _generation;
    final repository = _repository;
    final current = state;
    // Mid-reload the visible value belongs to the previous server.
    if (current.isLoading && repository == null) return;
    final previous = current is AsyncData<LibraryState> ? current.value : null;
    if (repository == null) {
      ref.invalidateSelf();
      await future;
      return;
    }
    _skipped = 0;
    final result = await repository.load();
    if (!ref.mounted || generation != _generation) return;
    final error = result.errorOrNull;
    if (error != null &&
        previous is LibraryData &&
        kOfflineFallbackCategories.contains(error.category)) {
      logOfflineFallback(ref.read(loggerProvider), 'sonarr', error);
      state = AsyncData(LibraryData(previous.snapshot.withOfflineError(error)));
      return;
    }
    state = AsyncData(_toState(result));
  }

  LibraryState _toState(Result<SeriesSnapshot> result) => result.when(
    ok: (snapshot) => LibraryData(
      snapshot.offlineError == null ? snapshot.withSkipped(_skipped) : snapshot,
    ),
    err: LibraryFailure.new,
  );
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
