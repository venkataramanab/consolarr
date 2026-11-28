// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/data/radarr_prefs.dart';
import 'package:consolarr/features/radarr/data/radarr_repository.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/domain/wanted.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/shared/logging/log_events.dart';
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

/// The active context, waiting for it when it is still resolving.
Future<RadarrContext?> _activeContext(Ref ref) async {
  final now = ref.read(radarrContextProvider).value;
  if (now != null) return now;
  try {
    return await ref.read(radarrContextProvider.future);
  } on Object {
    return null;
  }
}

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
    final gen = ++_generation;
    _context = null;
    final RadarrContext? context;
    try {
      context = await ref.watch(radarrContextProvider.future);
    } on AppError catch (error) {
      return RadarrFailure(error);
    }
    // A newer build owns the notifier now: its context must not be replaced.
    if (gen != _generation) return const RadarrNoServer();
    if (context == null) return const RadarrNoServer();
    _context = context;
    final result = await load(context);
    if (gen != _generation) return const RadarrNoServer();
    return _toState(result);
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
      logOfflineFallback(ref.read(loggerProvider), 'radarr', error);
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

/// Runs [computation], possibly on another isolate. Tests inject an inline
/// version.
typedef MovieRunner = Future<T> Function<T>(T Function() computation);

final movieRunnerProvider = Provider<MovieRunner>(
  (ref) =>
      <T>(T Function() computation) => Isolate.run(computation),
);

/// Libraries up to this size are filtered on the UI isolate (well under a
/// frame); bigger ones go to another isolate.
const movieSyncLimit = 1500;

/// The list the library screen shows: filtered, searched, sorted and grouped.
class VisibleMovies {
  const VisibleMovies({
    this.movies = const [],
    this.groups = const [],
    this.computing = false,
  });

  final List<RadarrMovie> movies;
  final List<MovieGroup> groups;

  /// A big list is being recomputed; [movies] is the previous result.
  final bool computing;
}

/// Library after search, filter and sort. Empty until the library is loaded.
/// The previous result stays visible while a big list is recomputed on
/// another isolate; a stale result is dropped.
final visibleMoviesProvider =
    NotifierProvider<VisibleMoviesNotifier, VisibleMovies>(
      VisibleMoviesNotifier.new,
    );

class VisibleMoviesNotifier extends Notifier<VisibleMovies> {
  int _generation = 0;
  VisibleMovies _last = const VisibleMovies();

  @override
  VisibleMovies build() {
    final library = ref.watch(movieLibraryProvider);
    final query = ref.watch(libraryQueryProvider);
    // A failed profile list only means no names.
    final profiles = ref.watch(qualityProfilesProvider).value ?? const [];
    final names = {for (final p in profiles) p.id: p.name};
    final runner = ref.read(movieRunnerProvider);
    final generation = ++_generation;
    // While loading or failed the value belongs to another state or server.
    if (library.isLoading || library.hasError) {
      return _last = const VisibleMovies();
    }
    final data = library.value;
    if (data is! RadarrData<List<RadarrMovie>>) {
      return _last = const VisibleMovies();
    }
    final all = data.value;
    if (all.length <= movieSyncLimit) {
      return _last = _visible(all, query, names);
    }
    unawaited(
      _computeVisible(runner, all, query, names).then(
        (result) {
          if (!ref.mounted || generation != _generation) return;
          state = _last = result;
        },
        onError: (Object error) {
          if (!ref.mounted || generation != _generation) return;
          // Keep the previous results; only the error category is logged.
          ref
              .read(breadcrumbsProvider)
              .add(
                Breadcrumb.apiError(
                  ErrorCategoryParam.parseError,
                  ServiceKindParam.radarr,
                ),
              );
          state = VisibleMovies(movies: _last.movies, groups: _last.groups);
        },
      ),
    );
    return VisibleMovies(
      movies: _last.movies,
      groups: _last.groups,
      computing: true,
    );
  }
}

VisibleMovies _visible(
  List<RadarrMovie> all,
  MovieQuery query,
  Map<int, String> names,
) {
  final rows = applyQuery(all, query, profileNames: names);
  return VisibleMovies(movies: rows, groups: groupMovies(rows, query.sort));
}

/// A function of its own so the closure sent to another isolate captures only
/// plain data, never the notifier.
Future<VisibleMovies> _computeVisible(
  MovieRunner runner,
  List<RadarrMovie> all,
  MovieQuery query,
  Map<int, String> names,
) => runner(() => _visible(all, query, names));

/// Wanted movies of one scope, computed once per library, clock and scope:
/// rebuilding the list never sorts again.
final wantedMoviesProvider = Provider.autoDispose
    .family<List<RadarrMovie>, WantedScope>((ref, scope) {
      final state = ref.watch(movieLibraryProvider).value;
      if (state is! RadarrData<List<RadarrMovie>>) return const [];
      return wantedMovies(state.value, scope, ref.watch(clockProvider)());
    });

// --- Shared lists -----------------------------------------------------------

/// A shared list: a failure is the provider's `AsyncError` (an [AppError]),
/// shown with a retry by the screens, never an empty list.
Future<List<T>> _sharedList<T>(
  Ref ref,
  Future<Result<List<T>>> Function(RadarrApi api) read,
) async {
  final context = await ref.watch(radarrContextProvider.future);
  if (context == null) return const [];
  final result = await read(context.api);
  final error = result.errorOrNull;
  if (error != null) {
    recordApiError(ref.read(breadcrumbsProvider), error);
    throw error;
  }
  return result.valueOrNull ?? const [];
}

final qualityProfilesProvider = FutureProvider<List<ArrQualityProfile>>(
  retry: _noRetry,
  (ref) => _sharedList(ref, (api) => api.qualityProfiles()),
);

final tagsProvider = FutureProvider<List<ArrTag>>(
  retry: _noRetry,
  (ref) => _sharedList(ref, (api) => api.tags()),
);

final rootFoldersProvider = FutureProvider<List<ArrRootFolder>>(
  retry: _noRetry,
  (ref) => _sharedList(ref, (api) => api.rootFolders()),
);

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

  /// An id that cannot exist (not a positive number) is "gone" at once; no
  /// request is made.
  @override
  Future<RadarrState<RadarrMovie>> build() =>
      movieId <= 0 ? Future.value(const RadarrGone()) : super.build();

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
    final generation = _generation;
    final result = await context.api.updateMovie(
      movieId,
      monitored: monitored,
      qualityProfileId: qualityProfileId,
      minimumAvailability: minimumAvailability,
      tags: tags,
    );
    // The server was switched (or the screen left) while writing: the answer
    // belongs to the old server and must not touch this state or its library.
    if (!ref.mounted || generation != _generation) return null;
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

typedef QueueState = RadarrState<List<ArrQueueItem>>;

final queueProvider = AsyncNotifierProvider<QueueNotifier, QueueState>(
  QueueNotifier.new,
);

class QueueNotifier extends SnapshotNotifier<List<ArrQueueItem>> {
  @override
  Future<Result<Snapshot<List<ArrQueueItem>>>> load(
    RadarrContext context,
  ) async {
    final result = await context.api.queue();
    final at = ref.read(clockProvider)();
    return result.map((q) => Snapshot(value: q, fetchedAt: at));
  }

  /// Removes [item] with the chosen consequences. Returns the failure.
  Future<AppError?> remove(
    ArrQueueItem item, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) async {
    final context = _context;
    if (context == null) return const AppError(ErrorCategory.notFound);
    final generation = _generation;
    final result = await context.api.removeQueueItem(
      item.id,
      removeFromClient: removeFromClient,
      blocklist: blocklist,
    );
    // Server switched or screen left while removing: drop the answer.
    if (!ref.mounted || generation != _generation) return null;
    final error = result.errorOrNull;
    if (error != null) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      return error;
    }
    final current = state.value;
    if (current is RadarrData<List<ArrQueueItem>>) {
      replace([
        for (final q in current.value)
          if (q.id != item.id) q,
      ]);
    }
    unawaited(
      ref
          .read(eventTrackerProvider)
          .track(
            RadarrQueueItemRemovedEvent(
              removal: removalParam(removeFromClient, blocklist),
            ),
          ),
    );
    return null;
  }
}

/// Movie titles of the loaded library by id, for queue rows. Rebuilds only
/// when the set of titles changes.
final movieTitlesProvider = Provider<Map<int, String>>((ref) {
  final state = ref.watch(movieLibraryProvider).value;
  if (state is! RadarrData<List<RadarrMovie>>) return const {};
  return {for (final m in state.value) m.id: m.title};
});

RadarrRemovalParam removalParam(bool fromClient, ArrBlocklistChoice b) =>
    switch (b) {
      ArrBlocklistChoice.blocklistAndSearch =>
        RadarrRemovalParam.blocklistAndSearch,
      ArrBlocklistChoice.blocklistOnly => RadarrRemovalParam.blocklistOnly,
      ArrBlocklistChoice.none =>
        fromClient
            ? RadarrRemovalParam.removeNoBlocklist
            : RadarrRemovalParam.keepInClientNoBlocklist,
    };

// --- Automatic search (RAD-12, RAD-15) -------------------------------------

enum SearchPhase {
  starting,
  queued,
  searching,
  done,
  failed,

  /// Still running on the server after the polling cap: "check the queue".
  /// Neutral: it is not a failure.
  stillRunning,
}

/// Poll cadence of a running command; tests override it.
final commandPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

/// Upper bound on polls per command (about two minutes at the default).
const maxCommandPolls = 60;

/// Longest a search poll waits while the app is locked, in steps of
/// [commandPollIntervalProvider]; after that the search is "still running".
const _maxLockedWaits = 120;

/// `(serverId, movieId)`: a search of one server never shows on another
/// server's movie with the same number. Movie id `0` is "search all missing".
typedef SearchKey = (String, int);

/// Per-movie search progress. Auto-disposed: leaving every screen that shows
/// it, or switching the server, ends the polling.
final searchStatusProvider =
    NotifierProvider.autoDispose<
      SearchStatusNotifier,
      Map<SearchKey, SearchPhase>
    >(SearchStatusNotifier.new);

/// The phase of one movie on the active server (null: nothing running). A
/// row watches only its own entry.
final searchPhaseProvider = Provider.autoDispose.family<SearchPhase?, int>((
  ref,
  movieId,
) {
  final serverId = ref.watch(
    radarrContextProvider.select((c) => c.value?.serverId),
  );
  if (serverId == null) return null;
  return ref.watch(searchStatusProvider.select((m) => m[(serverId, movieId)]));
});

class SearchStatusNotifier extends Notifier<Map<SearchKey, SearchPhase>> {
  static const allMissingKey = 0;

  /// Bumped by every build (server switch): polls of an earlier build stop.
  int _generation = 0;

  String? _serverId;
  bool _built = false;

  @override
  Map<SearchKey, SearchPhase> build() {
    final serverId = ref.watch(
      radarrContextProvider.select((c) => c.value?.serverId),
    );
    // The context resolving for the first time is not a server switch: an
    // action started while it was loading keeps its build.
    final resolved = _built && _serverId == null && serverId != null;
    _built = true;
    _serverId = serverId;
    if (resolved) return state;
    _generation++;
    return const {};
  }

  /// A result that arrives for another build never leaves [key] busy.
  void _clearIfOpen(SearchKey key) {
    if (!ref.mounted) return;
    if (state[key] == SearchPhase.starting) _set(key, null);
  }

  void _set(SearchKey key, SearchPhase? phase) {
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
    int movieId,
    Future<Result<ArrCommand>> Function(RadarrApi api) start,
    RadarrSearchKindParam kind,
  ) async {
    // Resolve the context first: a first action can arrive while it is still
    // loading, and resolving it rebuilds this notifier (its generation bumps).
    // The generation belongs to the build that runs the action.
    final context =
        ref.read(radarrContextProvider).value ?? await _activeContext(ref);
    if (context == null || !ref.mounted) return;
    final generation = _generation;
    final key = (context.serverId, movieId);
    bool stale() =>
        !ref.mounted ||
        generation != _generation ||
        ref.read(radarrContextProvider).value?.serverId != context.serverId;

    final running = state[key];
    if (running != null &&
        running != SearchPhase.done &&
        running != SearchPhase.failed &&
        running != SearchPhase.stillRunning) {
      return;
    }
    // Mark busy before the first await so a second tap cannot start twice.
    _set(key, SearchPhase.starting);
    final started = await start(context.api);
    if (stale()) {
      _clearIfOpen(key);
      return;
    }
    final error = started.errorOrNull;
    if (error != null) {
      recordApiError(ref.read(breadcrumbsProvider), error);
      _set(key, SearchPhase.failed);
      return;
    }
    unawaited(
      ref
          .read(eventTrackerProvider)
          .track(RadarrSearchStartedEvent(kind: kind)),
    );
    var command = started.valueOrNull!;
    _set(key, _phase(command.status));
    final interval = ref.read(commandPollIntervalProvider);
    for (var i = 0; i < maxCommandPolls && !command.isTerminal; i++) {
      await Future<void>.delayed(interval);
      // Paused while locked, but not forever.
      var waited = 0;
      while (!stale() && ref.read(appLockedProvider)) {
        if (++waited > _maxLockedWaits) {
          _set(key, SearchPhase.stillRunning);
          return;
        }
        await Future<void>.delayed(interval);
      }
      if (stale()) return;
      final next = await context.api.command(command.id);
      if (stale()) return;
      if (next.errorOrNull != null) {
        recordApiError(ref.read(breadcrumbsProvider), next.errorOrNull!);
        _set(key, SearchPhase.failed);
        return;
      }
      command = next.valueOrNull!;
      _set(key, _phase(command.status));
    }
    if (!command.isTerminal) {
      _set(key, SearchPhase.stillRunning);
      _refreshAfterSearch();
      return;
    }
    if (command.isSuccess) _refreshAfterSearch();
  }

  /// A finished search may have queued a release or changed a movie.
  void _refreshAfterSearch() {
    if (ref.read(queueProvider.exists)) {
      unawaited(ref.read(queueProvider.notifier).refresh());
    }
    if (ref.read(movieLibraryProvider.exists)) {
      unawaited(ref.read(movieLibraryProvider.notifier).refresh());
    }
  }

  SearchPhase _phase(ArrCommandStatus s) => switch (s) {
    ArrCommandStatus.queued => SearchPhase.queued,
    ArrCommandStatus.started ||
    ArrCommandStatus.unknown => SearchPhase.searching,
    ArrCommandStatus.completed => SearchPhase.done,
    ArrCommandStatus.failed ||
    ArrCommandStatus.aborted ||
    ArrCommandStatus.cancelled ||
    ArrCommandStatus.orphaned => SearchPhase.failed,
  };

  void clear(int movieId) {
    final id = ref.read(radarrContextProvider).value?.serverId;
    if (id != null) _set((id, movieId), null);
  }
}

// --- Releases (RAD-13) -----------------------------------------------------

final releasesProvider = FutureProvider.autoDispose
    .family<Result<List<ArrRelease>>, int>((ref, movieId) async {
      final context = await ref.watch(radarrContextProvider.future);
      if (context == null) {
        return const Result.err(AppError(ErrorCategory.notFound));
      }
      final result = await context.api.releases(movieId);
      final error = result.errorOrNull;
      if (error != null) recordApiError(ref.read(breadcrumbsProvider), error);
      return result;
    });

/// Per-release download state.
enum GrabPhase {
  grabbing,
  grabbed,

  /// The server answered with a failure; nothing was sent.
  failed,

  /// The request may have reached the server (timeout, dropped connection).
  /// Retrying needs the queue check and an explicit confirmation.
  maybeSent,
}

/// Key of a release in [grabStatusProvider].
String grabKey(ArrRelease r) => '${r.indexerId}/${r.guid}';

/// Download states by [grabKey]. Lives as long as the app does (it is per
/// server): reopening the sheet shows what was already sent instead of
/// offering "Download" again.
final grabStatusProvider =
    NotifierProvider<GrabNotifier, Map<String, GrabPhase>>(GrabNotifier.new);

class GrabNotifier extends Notifier<Map<String, GrabPhase>> {
  /// Bumped by every build (server switch): a grab started on server A never
  /// shows up against a release of server B.
  int _generation = 0;

  String? _serverId;
  bool _built = false;

  @override
  Map<String, GrabPhase> build() {
    final serverId = ref.watch(
      radarrContextProvider.select((c) => c.value?.serverId),
    );
    // The context resolving for the first time is not a server switch: an
    // action started while it was loading keeps its build.
    final resolved = _built && _serverId == null && serverId != null;
    _built = true;
    _serverId = serverId;
    if (resolved) return state;
    _generation++;
    return const {};
  }

  /// Sends [release] to the download client once. Ignored while it is being
  /// grabbed or after it was grabbed: nothing retries by itself, so a dropped
  /// connection can never submit twice without a new explicit tap. A release
  /// in [GrabPhase.maybeSent] is only sent again with [confirmedResend], which
  /// the caller sets after [confirmQueued] found nothing and the user said
  /// "send again".
  Future<void> grab(ArrRelease release, {bool confirmedResend = false}) async {
    final key = grabKey(release);
    final current = state[key];
    if (current == GrabPhase.grabbing || current == GrabPhase.grabbed) return;
    if (current == GrabPhase.maybeSent && !confirmedResend) return;
    // Resolve the context first: a first tap can arrive while it is still
    // loading, and resolving it rebuilds this notifier (its generation bumps).
    // The generation belongs to the build that runs the grab.
    final context =
        ref.read(radarrContextProvider).value ?? await _activeContext(ref);
    if (context == null || !ref.mounted) return;
    final generation = _generation;
    if (state[key] == GrabPhase.grabbing) return;
    state = {...state, key: GrabPhase.grabbing};
    final result = await context.api.grab(release);
    if (!ref.mounted) return;
    if (generation != _generation) {
      // Another build owns the map now: never leave the key busy.
      if (state[key] == GrabPhase.grabbing) {
        state = {...state}..remove(key);
      }
      return;
    }
    final error = result.errorOrNull;
    if (error != null) recordApiError(ref.read(breadcrumbsProvider), error);
    state = {
      ...state,
      key: error == null
          ? GrabPhase.grabbed
          : switch (error.category) {
              ErrorCategory.timeout ||
              ErrorCategory.networkUnreachable ||
              ErrorCategory.parseError ||
              ErrorCategory.serverError => GrabPhase.maybeSent,
              _ => GrabPhase.failed,
            },
    };
    if (error == null) {
      unawaited(
        ref
            .read(eventTrackerProvider)
            .track(RadarrReleaseGrabbedEvent(wasRejected: release.isRejected)),
      );
    }
  }

  /// Whether queue item [item] is [release] for [movieId]: the same movie (when
  /// the queue item names one) and the download client's id inside the release
  /// guid, or the same title without case and surrounding space.
  static bool _isRelease(ArrQueueItem item, ArrRelease release, int movieId) {
    if (item.movieId != null && item.movieId != movieId) return false;
    final id = item.downloadId?.trim().toLowerCase();
    if (id != null &&
        id.length >= 16 &&
        release.guid.toLowerCase().contains(id)) {
      return true;
    }
    return item.title.trim().toLowerCase() ==
        release.title.trim().toLowerCase();
  }

  /// Marks the releases that are in the queue as grabbed (a reopened sheet
  /// must not offer "Download" for what is already on its way).
  Future<void> syncWithQueue(List<ArrRelease> releases, int movieId) async {
    final context = ref.read(radarrContextProvider).value;
    if (context == null) return;
    final generation = _generation;
    final result = await context.api.queue();
    if (!ref.mounted || generation != _generation) return;
    final items = result.valueOrNull;
    if (items == null) return;
    final next = {...state};
    for (final r in releases) {
      final key = grabKey(r);
      if (next[key] == GrabPhase.grabbing) continue;
      if (items.any((i) => _isRelease(i, r, movieId))) {
        next[key] = GrabPhase.grabbed;
      }
    }
    state = next;
  }

  /// For a [GrabPhase.maybeSent] release: looks for it in the download queue.
  /// Found means the first request did arrive; it is then shown as grabbed and
  /// `true` is returned. Not found, or the queue could not be read, is
  /// `false`: the caller must ask before sending again.
  ///
  /// The queue snapshot is bounded (5 pages of 200); a release beyond that is
  /// treated as "not queued" and the caller asks first.
  Future<bool> confirmQueued(ArrRelease release, int movieId) async {
    final key = grabKey(release);
    if (state[key] != GrabPhase.maybeSent) return false;
    final context = ref.read(radarrContextProvider).value;
    if (context == null) return false;
    final generation = _generation;
    final result = await context.api.queue();
    if (!ref.mounted || generation != _generation) return false;
    final items = result.valueOrNull;
    if (items == null || !items.any((i) => _isRelease(i, release, movieId))) {
      return false;
    }
    state = {...state, key: GrabPhase.grabbed};
    return true;
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

/// Adds movies. A function value so a screen can keep calling it after its
/// sheet was popped: it uses the provider's own `ref`, never a widget's.
final addMovieActionProvider =
    Provider<Future<AppError?> Function(AddMovieRequest)>(
      (ref) =>
          (request) => _addMovie(ref, request),
    );

/// Whether [error] leaves it open that the movie was added anyway.
bool _maybeAdded(AppError error) => switch (error.category) {
  ErrorCategory.timeout ||
  ErrorCategory.networkUnreachable ||
  ErrorCategory.parseError ||
  ErrorCategory.serverError => true,
  _ => false,
};

/// Adds [request]; returns the failure, if any. A success adds the movie to
/// the shown library and remembers the root folder.
///
/// Adding is not idempotent: after a timeout or a dropped connection the
/// library is read again, and when the movie is there the add counts as done
/// (no duplicate request, no error).
Future<AppError?> _addMovie(Ref ref, AddMovieRequest request) async {
  final context = await ref.read(radarrContextProvider.future);
  if (context == null) return const AppError(ErrorCategory.notFound);
  final result = await context.api.addMovie(request);
  var error = result.errorOrNull;
  if (error != null && _maybeAdded(error) && ref.mounted) {
    final tmdbId = request.lookup.tmdbId;
    final library = await context.api.movies();
    final movies = library.valueOrNull;
    if (movies != null &&
        tmdbId != null &&
        movies.any((m) => m.tmdbId == tmdbId)) {
      error = null;
    }
  }
  if (error != null) {
    if (ref.mounted) recordApiError(ref.read(breadcrumbsProvider), error);
    return error;
  }
  if (!ref.mounted) return null;
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
  if (!ref.mounted) return null;
  ref.invalidate(defaultRootFolderProvider);
  unawaited(
    ref
        .read(eventTrackerProvider)
        .track(
          RadarrMovieAddedEvent(
            searchAfterAdd: request.searchForMovie,
            withCollection:
                request.addCollection && request.lookup.collectionTitle != null,
          ),
        ),
  );
  if (ref.read(movieLibraryProvider.exists)) {
    unawaited(ref.read(movieLibraryProvider.notifier).refresh());
  }
  return null;
}
