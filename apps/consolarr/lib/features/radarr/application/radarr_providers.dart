// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/data/radarr_prefs.dart';
import 'package:consolarr/features/radarr/data/radarr_repository.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/src/images/secure_image_provider.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

export 'package:consolarr/features/radarr/data/radarr_repository.dart'
    show Snapshot;

Duration? _noRetry(int retryCount, Object error) => null;

/// Everything a Radarr screen needs from the active server.
class RadarrContext {
  RadarrContext({
    required this.api,
    required this.repository,
    required this.serverId,
    required this.dio,
  });

  final RadarrApi api;
  final RadarrRepository repository;
  final String serverId;
  final Dio dio;
}

/// The active Radarr server's context, or null when none is configured.
/// Rebuilds when the active server or its credentials change.
final radarrContextProvider = FutureProvider<RadarrContext?>(retry: _noRetry, (
  ref,
) async {
  final connection = await ref.watch(
    activeConnectionProvider(ServiceKind.radarr).future,
  );
  if (connection == null) return null;
  final api = RadarrClient(
    dio: connection.dio,
    onRowsSkipped: (count) =>
        ref.read(loggerProvider).info('skipped $count malformed rows'),
  );
  return RadarrContext(
    api: api,
    repository: RadarrRepository(
      api: api,
      cache: ref.watch(payloadCacheProvider),
      serverId: connection.profile.id,
      clock: ref.watch(clockProvider),
    ),
    serverId: connection.profile.id,
    dio: connection.dio,
  );
});

/// Records an API failure as a breadcrumb (category and kind only).
void recordApiError(Breadcrumbs breadcrumbs, AppError error) {
  final category = ErrorCategoryParam.values.where(
    (c) => c.code == error.category.code,
  );
  if (category.isEmpty) return;
  breadcrumbs.add(Breadcrumb.apiError(category.first, ServiceKindParam.radarr));
}

/// What a notifier shows when no server exists or loading failed.
sealed class RadarrState<T> {
  const RadarrState();
}

final class RadarrNoServer<T> extends RadarrState<T> {
  const RadarrNoServer();
}

/// Nothing to show: failed and nothing cached. `auth_failed`,
/// `unsupported_version` and TLS errors always end up here.
final class RadarrFailure<T> extends RadarrState<T> {
  const RadarrFailure(this.error);
  final AppError error;
}

/// The thing was deleted on the server (NAV-05).
final class RadarrGone<T> extends RadarrState<T> {
  const RadarrGone();
}

final class RadarrData<T> extends RadarrState<T> {
  const RadarrData(this.snapshot);
  final Snapshot<T> snapshot;
  T get value => snapshot.value;
  bool get isOffline => snapshot.isOffline;
}

typedef LibraryState = RadarrState<List<RadarrMovie>>;

/// Loads one snapshot-shaped resource with the shared reload semantics: a
/// generation counter, refresh that keeps content, stale results dropped.
abstract class SnapshotNotifier<T> extends AsyncNotifier<RadarrState<T>> {
  int _generation = 0;
  RadarrContext? _context;

  Future<Result<Snapshot<T>>> load(RadarrContext context);

  @override
  Future<RadarrState<T>> build() async {
    _generation++;
    _context = null;
    final RadarrContext? context;
    try {
      context = await ref.watch(radarrContextProvider.future);
    } on AppError catch (error) {
      return RadarrFailure(error);
    }
    if (context == null) return const RadarrNoServer();
    _context = context;
    return _toState(await load(context));
  }

  RadarrState<T> _toState(Result<Snapshot<T>> result) {
    final error = result.errorOrNull;
    if (error != null) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      if (error.category == ErrorCategory.notFound && goneOnNotFound) {
        return const RadarrGone();
      }
      return RadarrFailure(error);
    }
    return RadarrData(result.valueOrNull!);
  }

  /// A 404 means the thing no longer exists (detail pages).
  bool get goneOnNotFound => false;

  /// Reloads without clearing what is on screen.
  Future<void> refresh() async {
    final generation = _generation;
    final context = _context;
    final current = state;
    if (current.isLoading && context == null) return;
    if (context == null) {
      ref.invalidateSelf();
      await future;
      return;
    }
    final previous = current is AsyncData<RadarrState<T>>
        ? current.value
        : null;
    final result = await load(context);
    if (!ref.mounted || generation != _generation) return;
    final error = result.errorOrNull;
    if (error != null &&
        previous is RadarrData<T> &&
        kOfflineFallbackCategories.contains(error.category)) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      state = AsyncData(RadarrData(previous.snapshot.withOfflineError(error)));
      return;
    }
    state = AsyncData(_toState(result));
  }

  /// Replaces the shown value after a successful write.
  void replace(T value) {
    final current = state.value;
    if (current is RadarrData<T>) {
      state = AsyncData(
        RadarrData(
          Snapshot(value: value, fetchedAt: current.snapshot.fetchedAt),
        ),
      );
    }
  }
}

// --- Library (RAD-01..05) -------------------------------------------------

final movieLibraryProvider =
    AsyncNotifierProvider<MovieLibraryNotifier, LibraryState>(
      MovieLibraryNotifier.new,
    );

class MovieLibraryNotifier extends SnapshotNotifier<List<RadarrMovie>> {
  @override
  Future<Result<Snapshot<List<RadarrMovie>>>> load(RadarrContext context) =>
      context.repository.library();
}

final radarrPrefsProvider = Provider<RadarrPrefs>(
  (ref) => DriftRadarrPrefs(ref.watch(databaseProvider)),
);

enum LibraryViewMode { grid, list }

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
      final saved = await ref
          .read(radarrPrefsProvider)
          .read(RadarrPrefKeys.viewMode);
      if (!ref.mounted) return;
      for (final m in LibraryViewMode.values) {
        if (m.name == saved) state = m;
      }
    } on Object {
      // Keep the default.
    }
  }

  Future<void> set(LibraryViewMode mode) async {
    state = mode;
    try {
      await ref
          .read(radarrPrefsProvider)
          .write(RadarrPrefKeys.viewMode, mode.name);
    } on Object {
      // Applies for this session.
    }
  }
}

/// Sort, filter and search of the library. The saved defaults are per server
/// and only written on an explicit "save as default" (RAD-03/04).
final libraryQueryProvider = NotifierProvider<LibraryQueryNotifier, MovieQuery>(
  LibraryQueryNotifier.new,
);

class LibraryQueryNotifier extends Notifier<MovieQuery> {
  String? _serverId;

  @override
  MovieQuery build() {
    final context = ref.watch(radarrContextProvider).value;
    final id = _serverId = context?.serverId;
    if (id != null) Future<void>.microtask(() => _restore(id));
    return const MovieQuery();
  }

  Future<void> _restore(String serverId) async {
    try {
      final prefs = ref.read(radarrPrefsProvider);
      final sort = await prefs.read(RadarrPrefKeys.librarySort(serverId));
      final filter = await prefs.read(RadarrPrefKeys.libraryFilter(serverId));
      if (!ref.mounted || _serverId != serverId) return;
      var q = state;
      if (sort != null) {
        final m = jsonDecode(sort);
        if (m is Map) {
          final key = MovieSortKey.values.where((k) => k.name == m['key']);
          q = q.copyWith(
            sort: key.isEmpty ? null : key.first,
            ascending: m['asc'] is bool ? m['asc'] as bool : null,
          );
        }
      }
      if (filter != null) {
        final m = jsonDecode(filter);
        if (m is Map) {
          q = q.copyWith(
            filter: MovieFilter.fromJson(m.cast<String, Object?>()),
          );
        }
      }
      state = q;
    } on Object {
      // Defaults stay.
    }
  }

  void setSearch(String value) => state = state.copyWith(search: value);

  Future<void> setSort(
    MovieSortKey key, {
    required bool ascending,
    bool saveAsDefault = false,
  }) async {
    state = state.copyWith(sort: key, ascending: ascending);
    final id = _serverId;
    if (saveAsDefault && id != null) {
      await _write(
        RadarrPrefKeys.librarySort(id),
        jsonEncode({'key': key.name, 'asc': ascending}),
      );
    }
  }

  Future<void> setFilter(
    MovieFilter filter, {
    bool saveAsDefault = false,
  }) async {
    state = state.copyWith(filter: filter);
    final id = _serverId;
    if (saveAsDefault && id != null) {
      await _write(
        RadarrPrefKeys.libraryFilter(id),
        jsonEncode(filter.toJson()),
      );
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await ref.read(radarrPrefsProvider).write(key, value);
    } on Object {
      // Applies for this session.
    }
  }
}

/// Library after search, filter and sort. Empty until the library is loaded.
final visibleMoviesProvider = Provider<List<RadarrMovie>>((ref) {
  final library = ref.watch(movieLibraryProvider);
  if (library.isLoading || library.hasError) return const [];
  final state = library.value;
  if (state is! RadarrData<List<RadarrMovie>>) return const [];
  final profiles = ref.watch(qualityProfilesProvider).value ?? const [];
  return applyQuery(
    state.value,
    ref.watch(libraryQueryProvider),
    profileNames: {for (final p in profiles) p.id: p.name},
  );
});

// --- Shared lists -----------------------------------------------------------

final qualityProfilesProvider = FutureProvider<List<ArrQualityProfile>>((
  ref,
) async {
  final context = await ref.watch(radarrContextProvider.future);
  if (context == null) return const [];
  return (await context.api.qualityProfiles()).valueOrNull ?? const [];
});

final tagsProvider = FutureProvider<List<ArrTag>>((ref) async {
  final context = await ref.watch(radarrContextProvider.future);
  if (context == null) return const [];
  return (await context.api.tags()).valueOrNull ?? const [];
});

final rootFoldersProvider = FutureProvider<List<ArrRootFolder>>((ref) async {
  final context = await ref.watch(radarrContextProvider.future);
  if (context == null) return const [];
  return (await context.api.rootFolders()).valueOrNull ?? const [];
});

// --- Artwork ---------------------------------------------------------------

/// Where artwork comes from: the active server's secure client.
class ArtworkSource {
  ArtworkSource({required this.dio, required RadarrApi api}) : _api = api;

  final Dio dio;
  final RadarrApi _api;

  ImageProvider? image(RadarrMovie movie, ArrImageType type) {
    final uri = _api.artworkUri(movie, type);
    return uri == null ? null : SecureNetworkImage(dio: dio, uri: uri);
  }

  ImageProvider? poster(RadarrMovie movie) => image(movie, ArrImageType.poster);
}

final artworkSourceProvider = Provider<ArtworkSource?>((ref) {
  final context = ref.watch(radarrContextProvider).value;
  if (context == null) return null;
  return ArtworkSource(dio: context.dio, api: context.api);
});

// --- Movie detail (RAD-08/09) ----------------------------------------------

final movieDetailProvider =
    AsyncNotifierProvider.family<
      MovieDetailNotifier,
      RadarrState<RadarrMovie>,
      int
    >(MovieDetailNotifier.new);

class MovieDetailNotifier extends SnapshotNotifier<RadarrMovie> {
  MovieDetailNotifier(this.movieId);

  final int movieId;

  @override
  bool get goneOnNotFound => true;

  @override
  Future<Result<Snapshot<RadarrMovie>>> load(RadarrContext context) =>
      context.repository.movie(movieId);

  /// Saves the editable fields (RAD-09). Returns the failure, if any.
  Future<AppError?> save({
    bool? monitored,
    int? qualityProfileId,
    MinimumAvailability? minimumAvailability,
    List<int>? tags,
  }) async {
    final context = _context;
    if (context == null) return const AppError(ErrorCategory.notFound);
    final result = await context.api.updateMovie(
      movieId,
      monitored: monitored,
      qualityProfileId: qualityProfileId,
      minimumAvailability: minimumAvailability,
      tags: tags,
    );
    final error = result.errorOrNull;
    if (error != null) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      return error;
    }
    final saved = result.valueOrNull!;
    replace(saved);
    // Keep the library list consistent without a reload.
    final lib = ref.read(movieLibraryProvider).value;
    if (lib is RadarrData<List<RadarrMovie>>) {
      ref.read(movieLibraryProvider.notifier).replace([
        for (final m in lib.value) m.id == saved.id ? saved : m,
      ]);
    }
    return null;
  }
}

// --- Calendar (RAD-10) -----------------------------------------------------

enum ReleaseType { cinema, digital, physical }

/// A release date of a movie on the calendar.
class CalendarEntry {
  const CalendarEntry(this.movie, this.type, this.date);
  final RadarrMovie movie;
  final ReleaseType type;
  final DateTime date;
}

List<CalendarEntry> calendarEntries(
  List<RadarrMovie> movies,
  Set<ReleaseType> types, {
  DateTime? from,
  DateTime? to,
}) {
  final out = <CalendarEntry>[];
  for (final m in movies) {
    for (final (type, date) in [
      (ReleaseType.cinema, m.inCinemas),
      (ReleaseType.digital, m.digitalRelease),
      (ReleaseType.physical, m.physicalRelease),
    ]) {
      if (date == null || !types.contains(type)) continue;
      if (from != null && date.isBefore(from)) continue;
      if (to != null && date.isAfter(to)) continue;
      out.add(CalendarEntry(m, type, date));
    }
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.movie.sortTitle.compareTo(b.movie.sortTitle);
  });
  return out;
}

/// The window the calendar loads, around [now].
(DateTime, DateTime) calendarRange(DateTime now) {
  final day = DateTime.utc(now.year, now.month, now.day);
  return (
    day.subtract(const Duration(days: 14)),
    day.add(const Duration(days: 120)),
  );
}

final calendarProvider =
    AsyncNotifierProvider<CalendarNotifier, RadarrState<List<RadarrMovie>>>(
      CalendarNotifier.new,
    );

class CalendarNotifier extends SnapshotNotifier<List<RadarrMovie>> {
  @override
  Future<Result<Snapshot<List<RadarrMovie>>>> load(RadarrContext context) {
    final (start, end) = calendarRange(ref.read(clockProvider)());
    return context.repository.calendar(start, end);
  }
}

final calendarTypesProvider =
    NotifierProvider<CalendarTypesNotifier, Set<ReleaseType>>(
      CalendarTypesNotifier.new,
    );

class CalendarTypesNotifier extends Notifier<Set<ReleaseType>> {
  @override
  Set<ReleaseType> build() => {...ReleaseType.values};

  void toggle(ReleaseType type) {
    final next = {...state};
    if (!next.remove(type)) next.add(type);
    // Never leave the calendar with no type at all.
    state = next.isEmpty ? {...ReleaseType.values} : next;
  }
}

// --- Queue (RAD-11) --------------------------------------------------------

typedef QueueState = RadarrState<List<RadarrQueueItem>>;

final queueProvider = AsyncNotifierProvider<QueueNotifier, QueueState>(
  QueueNotifier.new,
);

class QueueNotifier extends SnapshotNotifier<List<RadarrQueueItem>> {
  @override
  Future<Result<Snapshot<List<RadarrQueueItem>>>> load(
    RadarrContext context,
  ) async {
    final result = await context.api.queue();
    final at = ref.read(clockProvider)();
    return result.map((q) => Snapshot(value: q, fetchedAt: at));
  }

  /// Removes [item] with the chosen consequences. Returns the failure.
  Future<AppError?> remove(
    RadarrQueueItem item, {
    required bool removeFromClient,
    required QueueBlocklist blocklist,
  }) async {
    final context = _context;
    if (context == null) return const AppError(ErrorCategory.notFound);
    final result = await context.api.removeQueueItem(
      item.id,
      removeFromClient: removeFromClient,
      blocklist: blocklist,
    );
    final error = result.errorOrNull;
    if (error != null) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      return error;
    }
    final current = state.value;
    if (current is RadarrData<List<RadarrQueueItem>>) {
      replace([
        for (final q in current.value)
          if (q.id != item.id) q,
      ]);
    }
    unawaited(
      ref
          .read(eventTrackerProvider)
          .track(
            QueueItemRemovedEvent(
              removal: removalParam(removeFromClient, blocklist),
            ),
          ),
    );
    return null;
  }
}

RadarrRemovalParam removalParam(bool fromClient, QueueBlocklist b) =>
    switch (b) {
      QueueBlocklist.blocklistAndSearch =>
        RadarrRemovalParam.blocklistAndSearch,
      QueueBlocklist.blocklistOnly => RadarrRemovalParam.blocklistOnly,
      QueueBlocklist.none =>
        fromClient
            ? RadarrRemovalParam.removeNoBlocklist
            : RadarrRemovalParam.keepInClientNoBlocklist,
    };

// --- Automatic search (RAD-12, RAD-15) -------------------------------------

enum SearchPhase { starting, queued, searching, done, failed }

/// Poll cadence of a running command; tests override it.
final commandPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

/// Upper bound on polls per command (about two minutes at the default).
const maxCommandPolls = 60;

/// Per-movie search progress. `0` is the key of "search all missing".
final searchStatusProvider =
    NotifierProvider<SearchStatusNotifier, Map<int, SearchPhase>>(
      SearchStatusNotifier.new,
    );

class SearchStatusNotifier extends Notifier<Map<int, SearchPhase>> {
  static const allMissingKey = 0;

  @override
  Map<int, SearchPhase> build() => const {};

  void _set(int key, SearchPhase? phase) {
    final next = {...state};
    if (phase == null) {
      next.remove(key);
    } else {
      next[key] = phase;
    }
    state = next;
  }

  Future<void> searchMovie(int movieId) => _run(
    movieId,
    (api) => api.searchMovies([movieId]),
    RadarrSearchKindParam.movie,
  );

  Future<void> searchAllMissing() => _run(
    allMissingKey,
    (api) => api.searchAllMissing(),
    RadarrSearchKindParam.allMissing,
  );

  Future<void> _run(
    int key,
    Future<Result<RadarrCommand>> Function(RadarrApi api) start,
    RadarrSearchKindParam kind,
  ) async {
    final running = state[key];
    if (running != null &&
        running != SearchPhase.done &&
        running != SearchPhase.failed) {
      return;
    }
    final context = await ref.read(radarrContextProvider.future);
    if (context == null || !ref.mounted) return;
    _set(key, SearchPhase.starting);
    final started = await start(context.api);
    if (!ref.mounted) return;
    final error = started.errorOrNull;
    if (error != null) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      _set(key, SearchPhase.failed);
      return;
    }
    unawaited(
      ref.read(eventTrackerProvider).track(SearchStartedEvent(kind: kind)),
    );
    var command = started.valueOrNull!;
    _set(key, _phase(command.status));
    final interval = ref.read(commandPollIntervalProvider);
    for (var i = 0; i < maxCommandPolls && !command.isFinished; i++) {
      await Future<void>.delayed(interval);
      if (!ref.mounted) return;
      final next = await context.api.command(command.id);
      if (!ref.mounted) return;
      if (next.errorOrNull != null) {
        recordApiError(ref.read(breadcrumbsProvider), next.errorOrNull!);
        _set(key, SearchPhase.failed);
        return;
      }
      command = next.valueOrNull!;
      _set(key, _phase(command.status));
    }
    if (!command.isFinished) _set(key, SearchPhase.failed);
  }

  SearchPhase _phase(CommandStatus s) => switch (s) {
    CommandStatus.queued => SearchPhase.queued,
    CommandStatus.started || CommandStatus.unknown => SearchPhase.searching,
    CommandStatus.completed => SearchPhase.done,
    CommandStatus.failed || CommandStatus.aborted => SearchPhase.failed,
  };

  void clear(int key) => _set(key, null);
}

// --- Releases (RAD-13) -----------------------------------------------------

final releasesProvider = FutureProvider.autoDispose
    .family<Result<List<RadarrRelease>>, int>((ref, movieId) async {
      final context = await ref.watch(radarrContextProvider.future);
      if (context == null)
        return const Result.err(AppError(ErrorCategory.notFound));
      final result = await context.api.releases(movieId);
      final error = result.errorOrNull;
      if (error != null) recordApiError(ref.read(breadcrumbsProvider), error);
      return result;
    });

enum GrabPhase { grabbing, grabbed, failed }

final grabStatusProvider =
    NotifierProvider.autoDispose<GrabNotifier, Map<String, GrabPhase>>(
      GrabNotifier.new,
    );

class GrabNotifier extends Notifier<Map<String, GrabPhase>> {
  @override
  Map<String, GrabPhase> build() => const {};

  Future<void> grab(RadarrRelease release) async {
    if (state[release.guid] == GrabPhase.grabbing) return;
    final context = await ref.read(radarrContextProvider.future);
    if (context == null || !ref.mounted) return;
    state = {...state, release.guid: GrabPhase.grabbing};
    final result = await context.api.grab(release);
    if (!ref.mounted) return;
    final error = result.errorOrNull;
    if (error != null) recordApiError(ref.read(breadcrumbsProvider), error);
    state = {
      ...state,
      release.guid: error == null ? GrabPhase.grabbed : GrabPhase.failed,
    };
    if (error == null) {
      unawaited(
        ref
            .read(eventTrackerProvider)
            .track(ReleaseGrabbedEvent(wasRejected: release.rejected)),
      );
    }
  }
}

// --- Add movie (RAD-14) ----------------------------------------------------

/// A lookup result row plus whether it is already in the library.
sealed class LookupState {
  const LookupState();
}

final class LookupIdle extends LookupState {
  const LookupIdle();
}

final class LookupSearching extends LookupState {
  const LookupSearching();
}

final class LookupResults extends LookupState {
  const LookupResults(this.movies);
  final List<RadarrMovie> movies;
}

final class LookupFailed extends LookupState {
  const LookupFailed(this.error);
  final AppError error;
}

final movieLookupProvider =
    NotifierProvider.autoDispose<MovieLookupNotifier, LookupState>(
      MovieLookupNotifier.new,
    );

class MovieLookupNotifier extends Notifier<LookupState> {
  int _seq = 0;

  @override
  LookupState build() => const LookupIdle();

  Future<void> search(String term) async {
    final t = term.trim();
    final seq = ++_seq;
    if (t.isEmpty) {
      state = const LookupIdle();
      return;
    }
    state = const LookupSearching();
    final context = await ref.read(radarrContextProvider.future);
    if (context == null || !ref.mounted || seq != _seq) return;
    final result = await context.api.lookup(t);
    if (!ref.mounted || seq != _seq) return;
    final error = result.errorOrNull;
    if (error != null) recordApiError(ref.read(breadcrumbsProvider), error);
    state = error != null
        ? LookupFailed(error)
        : LookupResults(result.valueOrNull!);
  }
}

/// The remembered default root folder path of the active server.
final defaultRootFolderProvider = FutureProvider<String?>((ref) async {
  final context = await ref.watch(radarrContextProvider.future);
  if (context == null) return null;
  return ref
      .read(radarrPrefsProvider)
      .read(RadarrPrefKeys.defaultRootFolder(context.serverId));
});

/// Adds [request]; returns the failure, if any. A success adds the movie to
/// the shown library and remembers the root folder.
Future<AppError?> addMovie(WidgetRef ref, AddMovieRequest request) async {
  final context = await ref.read(radarrContextProvider.future);
  if (context == null) return const AppError(ErrorCategory.notFound);
  final result = await context.api.addMovie(request);
  final error = result.errorOrNull;
  if (error != null) {
    recordApiError(ref.read(breadcrumbsProvider), error);
    return error;
  }
  try {
    await ref
        .read(radarrPrefsProvider)
        .write(
          RadarrPrefKeys.defaultRootFolder(context.serverId),
          request.rootFolderPath,
        );
  } on Object {
    // Optional convenience.
  }
  ref.invalidate(defaultRootFolderProvider);
  unawaited(
    ref
        .read(eventTrackerProvider)
        .track(
          MovieAddedEvent(
            searchAfterAdd: request.searchForMovie,
            withCollection:
                request.addCollection && request.lookup.collectionTitle != null,
          ),
        ),
  );
  unawaited(ref.read(movieLibraryProvider.notifier).refresh());
  return null;
}
