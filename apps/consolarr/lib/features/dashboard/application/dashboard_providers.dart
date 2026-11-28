// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_cancel.dart';
import 'package:consolarr/features/dashboard/application/dashboard_dates.dart';
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/application/dashboard_sources.dart';
import 'package:consolarr/features/dashboard/data/dashboard_cache.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart'
    show ServerCredentials;
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart' show CancelToken, Dio;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:observability/observability.dart';

/// Why a refresh runs.
enum DashboardTrigger {
  pull(DashboardTriggerParam.pull),
  poll(DashboardTriggerParam.poll),
  retry(DashboardTriggerParam.retry),
  resume(DashboardTriggerParam.resume);

  const DashboardTrigger(this.param);

  final DashboardTriggerParam param;

  /// The user asked for it (shown at once, announced once).
  bool get userInitiated => this != poll;
}

/// The sources per kind. Override in tests (a counting fake).
final dashboardSourcesProvider = Provider<Map<ServiceKind, DashboardSource>>(
  (ref) => dashboardSources,
);

/// Seconds between activity polls while the dashboard is visible.
final dashboardPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

/// How long one source may take before its slice fails with `timeout`; a hung
/// server never delays the others.
final dashboardDeadlineProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 20),
);

/// Upcoming and recent refresh on a poll only when older than this.
final dashboardMediaMaxAgeProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 5),
);

/// Background polls keep the previous activity this many failures before the
/// slice shows the failure (a user action reports at once).
const dashboardPollFailuresUntilError = 3;

/// `debugDetail` of the error an unexpected throwable becomes.
const kUnexpectedDetail = 'unexpected';

/// Upcoming and recent keep what is on screen through this many failed polls
/// in a row; the last one shows the failure (a user action reports at once).
const dashboardMediaPollFailuresUntilError = 2;

/// The first wait before a failed upcoming or recent request is tried again by
/// a poll; it doubles with every failure, up to [dashboardMediaMaxAgeProvider].
const dashboardMediaRetryBase = Duration(seconds: 30);

/// Replaces the isolate runner of the clients (tests).
final dashboardParseRunnerProvider = Provider<ParseRunner?>((ref) => null);

/// Reads the stored credentials of a server (a seam for tests; clients that
/// log in themselves need them).
final dashboardCredentialLoaderProvider =
    Provider<Future<ServerCredentials> Function(ServerProfile profile)>(
      (ref) =>
          (profile) =>
              ref.read(serverRepositoryProvider).loadCredentials(profile),
    );

/// The ids of every stored server, or `null` when they cannot be read (a seam
/// for tests). Used to drop cache rows of servers that are gone.
final dashboardServerIdsProvider = Provider<Future<Set<String>?> Function()>(
  (ref) => () async {
    final entries = await ref.read(serverRepositoryProvider).watchAll().first;
    return {for (final e in entries) e.profile.id};
  },
);

/// The dashboard's last-good copy of upcoming and recent items.
final dashboardCacheProvider = Provider<DashboardCache>(
  (ref) => DashboardCache(ref.watch(payloadCacheProvider)),
);

/// What the dashboard shows: one sealed state per card, each with one slice
/// per server. Nothing is read before the first frame.
final dashboardProvider =
    NotifierProvider<DashboardNotifier, DashboardSnapshot>(
      DashboardNotifier.new,
      retry: _noRetry,
    );

Duration? _noRetry(int retryCount, Object error) => null;

/// One request group's slot of a card.
class _Slot {
  CardSlice<Object?>? slice;
  DateTime? loadedAt;

  /// When the last request of this slot started (back-off of failed media
  /// slices).
  DateTime? lastAttempt;
  int failures = 0;
  Future<bool>? inFlight;

  /// The request in flight, so a deadline, a connection change or dispose can
  /// cancel it.
  CancelToken? cancel;

  /// A user action joined the request in flight: its result is reported as the
  /// user's, not as a poll's.
  bool userJoined = false;
}

/// What the dashboard knows about the active server of one kind.
class _Kind {
  _Kind(this.kind);

  final ServiceKind kind;

  /// Bumped on every connection change of this kind, so answers of the
  /// previous server are dropped. Other kinds are unaffected.
  int generation = 0;
  bool resolved = false;
  ServerConnection? connection;
  AppError? connectionError;
  String serverId = '';
  String serverName = '';
  SourceSession? session;

  /// The connection's Dio whose requests can be cancelled.
  Dio? dio;
  final Map<DashboardCard, _Slot> slots = {
    for (final c in DashboardCard.values) c: _Slot(),
  };
}

class DashboardNotifier extends Notifier<DashboardSnapshot> {
  /// Bumped by every `build()` (first frame, provider rebuild).
  int _build = 0;
  bool _building = false;
  Map<ServiceKind, DashboardSource> _sources = const {};
  final Map<ServiceKind, _Kind> _kinds = {};

  @override
  DashboardSnapshot build() {
    _build++;
    _closeSessions();
    _kinds.clear();
    _sources = ref.watch(dashboardSourcesProvider);
    // Nothing is read before the first frame.
    if (!ref.watch(firstFrameDoneProvider)) return const DashboardSnapshot();
    ref.onDispose(_closeSessions);
    unawaited(Future(_pruneCache));
    _building = true;
    try {
      for (final kind in _sources.keys) {
        _kinds[kind] = _Kind(kind);
        ref.listen<AsyncValue<ServerConnection?>>(
          activeConnectionProvider(kind),
          (_, next) => _onConnection(kind, next),
          fireImmediately: true,
        );
      }
    } finally {
      _building = false;
    }
    return _compose();
  }

  void _closeSessions() {
    for (final k in _kinds.values) {
      _cancelRequests(k);
      k.session?.close();
      k.session = null;
    }
  }

  /// Cancels every request of [k] still on the wire.
  void _cancelRequests(_Kind k) {
    for (final slot in k.slots.values) {
      slot.cancel?.cancel();
      slot.cancel = null;
    }
  }

  /// Once after the first frame: cached rows of servers that no longer exist
  /// (a delete that raced with a refresh) are dropped. No I/O before.
  Future<void> _pruneCache() async {
    try {
      final ids = await ref.read(dashboardServerIdsProvider)();
      if (ids == null || !ref.mounted) return;
      await ref.read(dashboardCacheProvider).prune(ids);
    } on Object {
      // The rows are harmless: they are only read for an existing server.
    }
  }

  /// Drops the cached rows of [serverId] when that server was deleted.
  Future<void> _forgetIfDeleted(String serverId) async {
    try {
      final ids = await ref.read(dashboardServerIdsProvider)();
      if (ids == null || ids.contains(serverId)) return;
      await ref.read(dashboardCacheProvider).deleteServer(serverId);
    } on Object {
      // Nothing to do: the next start prunes.
    }
  }

  Future<bool> _serverExists(String serverId) async {
    try {
      final ids = await ref.read(dashboardServerIdsProvider)();
      return ids == null || ids.contains(serverId);
    } on Object {
      return true;
    }
  }

  // --- connections ------------------------------------------------------------

  void _onConnection(ServiceKind kind, AsyncValue<ServerConnection?> value) {
    final k = _kinds[kind];
    if (k == null || !ref.mounted) return;
    final previousId = k.connection?.profile.id ?? '';
    k.generation++;
    _cancelRequests(k);
    k.session?.close();
    k.session = null;
    k.dio = null;
    for (final slot in k.slots.values) {
      slot
        ..slice = null
        ..loadedAt = null
        ..lastAttempt = null
        ..failures = 0
        ..userJoined = false
        ..inFlight = null;
    }
    // A server that is gone leaves no titles behind, whatever a request still
    // in flight did.
    if (previousId.isNotEmpty) unawaited(_forgetIfDeleted(previousId));
    k.connection = null;
    k.connectionError = null;
    if (value.isLoading) {
      k.resolved = false;
    } else if (value.hasError) {
      k.resolved = true;
      final error = _asAppError(value.error);
      k.connectionError = error;
      k.serverId = kind.name;
      k.serverName = '';
      unawaited(_identify(k, k.generation));
      for (final card in DashboardCard.values) {
        if (!_sources[kind]!.feeds(card)) continue;
        k.slots[card]!.slice = SliceFailed(
          serverId: k.serverId,
          serverName: k.serverName,
          kind: kind,
          error: error,
        );
      }
      _recordError(kind, error);
    } else {
      k.resolved = true;
      final connection = value.value;
      if (connection != null) {
        k.connection = connection;
        k.serverId = connection.profile.id;
        k.serverName = connection.profile.name;
        k.session = SourceSession();
        k.dio = cancellableDio(connection.dio);
        for (final card in DashboardCard.values) {
          if (!_sources[kind]!.feeds(card)) continue;
          k.slots[card]!.slice = SliceLoading(
            serverId: k.serverId,
            serverName: k.serverName,
            kind: kind,
          );
        }
      }
    }
    _publish();
    if (k.connection != null) {
      unawaited(_loadKind(k, DashboardCard.values.toSet(), trigger: null));
    }
  }

  /// The id and name of the server a failed connection belongs to, filled in
  /// once the server list answers (the error slice names the service
  /// meanwhile).
  Future<void> _identify(_Kind k, int generation) async {
    try {
      final key = await _firstValue(activeConnectionKeyProvider(k.kind));
      final id = key.serverId;
      if (id == null) return;
      final entries = await _firstValue(serversProvider);
      if (!ref.mounted || k.generation != generation) return;
      k.serverId = id;
      for (final e in entries) {
        if (e.profile.id == id) k.serverName = e.profile.name;
      }
      final error = k.connectionError;
      if (error == null) return;
      for (final card in DashboardCard.values) {
        if (!_sources[k.kind]!.feeds(card)) continue;
        k.slots[card]!.slice = SliceFailed(
          serverId: k.serverId,
          serverName: k.serverName,
          kind: k.kind,
          error: error,
        );
      }
      _publish();
    } on Object {
      // The error slice still names the service.
    }
  }

  /// The first value of a stream provider. A listener is needed: Riverpod
  /// pauses providers nobody listens to, so a plain `read(...future)` of a
  /// stream would never emit.
  Future<T> _firstValue<T>(ProviderListenable<AsyncValue<T>> provider) {
    final done = Completer<T>();
    final sub = ref.listen<AsyncValue<T>>(provider, (_, next) {
      if (done.isCompleted) return;
      if (next.hasValue) {
        done.complete(next.value as T);
      } else if (next.hasError) {
        done.completeError(next.error!);
      }
    }, fireImmediately: true);
    return done.future
        .timeout(const Duration(seconds: 5))
        .whenComplete(sub.close);
  }

  // --- refreshing -------------------------------------------------------------

  /// Refreshes for [trigger]; completes when every request group answered or
  /// hit its deadline. Slices update as each one answers. Overlapping calls
  /// join the request already in flight; kinds that are still resolving their
  /// connection are skipped. Returns `false` when every activity request of a
  /// background poll failed (the scheduler then backs off).
  Future<bool> refresh(DashboardTrigger trigger) async {
    final build = _build;
    final runs = <(_Kind, Future<Map<DashboardCard, bool>>)>[];
    for (final k in _kinds.values) {
      if (k.connection == null) continue;
      final cards = <DashboardCard>{};
      for (final card in DashboardCard.values) {
        if (!_sources[k.kind]!.feeds(card)) continue;
        if (trigger == DashboardTrigger.poll &&
            card != DashboardCard.activity &&
            !_isStale(k.slots[card]!)) {
          continue;
        }
        cards.add(card);
      }
      if (cards.isEmpty) continue;
      runs.add((k, _loadKind(k, cards, trigger: trigger)));
    }
    if (runs.isEmpty) return true;
    final results = await Future.wait([for (final r in runs) r.$2]);
    if (!ref.mounted || build != _build) return true;
    _report(
      trigger,
      servers: runs.length,
      failed: results.where((r) => r.values.any((ok) => !ok)).length,
    );
    if (trigger == DashboardTrigger.poll) {
      // Only the activity answers decide the back-off.
      final answers = [
        for (final r in results)
          if (r.containsKey(DashboardCard.activity)) r[DashboardCard.activity]!,
      ];
      return answers.isEmpty || answers.any((ok) => ok);
    }
    return true;
  }

  /// Retries the failed servers of [card] (retry button).
  Future<void> retry(DashboardCard card) async {
    final failed = [
      for (final k in _kinds.values)
        if (k.slots[card]!.slice is SliceFailed) k,
    ];
    if (failed.isEmpty) return;
    final build = _build;
    for (final k in failed) {
      final slice = k.slots[card]!.slice! as SliceFailed;
      final category = ErrorCategoryParam.values.where(
        (c) => c.code == slice.error.category.code,
      );
      if (category.isNotEmpty) {
        ref
            .read(eventTrackerProvider)
            .track(
              DashboardCardRetriedEvent(
                card: _cardParam(card),
                errorCategory: category.first,
              ),
            );
      }
    }
    // A failed connection is retried by asking for the connection again.
    for (final k in failed) {
      if (k.connection == null)
        ref.invalidate(activeConnectionProvider(k.kind));
    }
    final runs = [
      for (final k in failed)
        if (k.connection != null) _loadKind(k, {card}, trigger: null),
    ];
    final results = await Future.wait(runs);
    if (!ref.mounted || build != _build) return;
    _report(
      DashboardTrigger.retry,
      servers: runs.length,
      failed: results.where((r) => r.values.any((ok) => !ok)).length,
    );
  }

  /// Whether a poll should ask for [slot] again: it is older than the media
  /// age and, after failures, the back-off since the last try has passed.
  bool _isStale(_Slot slot) {
    final now = ref.read(clockProvider)();
    final maxAge = ref.read(dashboardMediaMaxAgeProvider);
    final at = slot.loadedAt;
    if (at != null && now.difference(at) < maxAge) return false;
    final attempt = slot.lastAttempt;
    if (slot.failures == 0 || attempt == null) return true;
    final steps = (slot.failures - 1).clamp(0, 10);
    var wait = dashboardMediaRetryBase * (1 << steps);
    if (wait > maxAge) wait = maxAge;
    return now.difference(attempt) >= wait;
  }

  /// Loads [cards] of one kind (one request group). Returns whether every
  /// card of the group succeeded. [trigger] `null` is the first load after the
  /// connection changed.
  Future<Map<DashboardCard, bool>> _loadKind(
    _Kind k,
    Set<DashboardCard> cards, {
    required DashboardTrigger? trigger,
  }) async {
    final asked = [
      for (final card in DashboardCard.values)
        if (cards.contains(card) && _sources[k.kind]!.feeds(card)) card,
    ];
    final results = await Future.wait([
      for (final card in asked) _loadCard(k, card, trigger),
    ]);
    return {for (var i = 0; i < asked.length; i++) asked[i]: results[i]};
  }

  Future<bool> _loadCard(
    _Kind k,
    DashboardCard card,
    DashboardTrigger? trigger,
  ) {
    final slot = k.slots[card]!;
    // Overlapping refreshes coalesce.
    final running = slot.inFlight;
    if (running != null) {
      // A user action that joins a poll gets its result reported as its own.
      if (trigger != null && trigger.userInitiated) slot.userJoined = true;
      return running;
    }
    slot.userJoined = false;
    late final Future<bool> future;
    future = _fetchCard(k, card, trigger).whenComplete(() {
      // Only the request that is still the slot's current one clears it: a
      // late answer of the previous server must not drop the new one.
      if (identical(slot.inFlight, future)) slot.inFlight = null;
    });
    slot.inFlight = future;
    return future;
  }

  Future<bool> _fetchCard(
    _Kind k,
    DashboardCard card,
    DashboardTrigger? trigger,
  ) async {
    final connection = k.connection;
    final session = k.session;
    final dio = k.dio;
    if (connection == null || session == null || dio == null) return true;
    final generation = k.generation;
    final build = _build;
    bool stale() =>
        !ref.mounted || k.generation != generation || build != _build;

    final slot = k.slots[card]!;
    final source = _sources[k.kind]!;
    final now = ref.read(clockProvider)();
    slot.lastAttempt = now;
    final token = CancelToken();
    slot.cancel = token;
    final context = SourceContext(
      connection: connection,
      dio: dio,
      loadCredentials: () =>
          ref.read(dashboardCredentialLoaderProvider)(connection.profile),
      session: session,
      now: now,
      utcOffset: now.timeZoneOffset,
      runner: ref.read(dashboardParseRunnerProvider),
      onRowsSkipped: (count) => ref
          .read(loggerProvider)
          .info('dashboard skipped $count malformed rows'),
    );
    final deadline = ref.read(dashboardDeadlineProvider);

    Future<Result<Object?>> run() async {
      switch (card) {
        case DashboardCard.activity:
          return (await source.activity!(context)).map<Object?>((v) => v);
        case DashboardCard.upcoming:
          return (await source.upcoming!(context)).map<Object?>((v) => v);
        case DashboardCard.recent:
          return (await source.recent!(context)).map<Object?>((v) => v);
      }
    }

    Result<Object?> result;
    try {
      result = await runCancellable(token, run).timeout(
        deadline,
        onTimeout: () {
          // Close the socket: a hung server must not collect connections.
          token.cancel();
          return const Result.err(AppError(ErrorCategory.timeout));
        },
      );
    } on Object catch (e) {
      result = Result.err(_asAppError(e));
    }
    if (identical(slot.cancel, token)) slot.cancel = null;
    if (stale()) return true;

    final error = result.errorOrNull;
    if (error == null) {
      final value = result.valueOrNull;
      slot
        ..failures = 0
        ..loadedAt = ref.read(clockProvider)()
        ..slice = SliceData<Object?>(
          serverId: k.serverId,
          serverName: k.serverName,
          kind: k.kind,
          value: value,
        );
      _publish();
      if (card != DashboardCard.activity && value is List<MediaItem>) {
        await _cacheWrite(k, card, value, slot.loadedAt!, generation);
      }
      return true;
    }

    _recordError(k.kind, error);
    slot.failures++;
    final previous = slot.slice;
    // A transient failure of a background poll keeps what is on screen; a user
    // action (even one that joined this poll) reports at once.
    final poll = trigger == DashboardTrigger.poll && !slot.userJoined;
    if (poll && previous is SliceData) {
      final limit = card == DashboardCard.activity
          ? dashboardPollFailuresUntilError
          : dashboardMediaPollFailuresUntilError;
      if (slot.failures < limit) return false;
    }
    // Last good copy: only for reachability failures, never after
    // `auth_failed`, `unsupported_version`, a TLS error or an unexpected
    // error, and never for the live activity card.
    if (card != DashboardCard.activity &&
        error.debugDetail != kUnexpectedDetail &&
        kOfflineFallbackCategories.contains(error.category)) {
      final today = calendarDay(now, now.timeZoneOffset);
      final cached = await ref
          .read(dashboardCacheProvider)
          .read(k.serverId, card, connection.dio, today: today);
      if (stale()) return false;
      if (cached != null) {
        slot.slice = SliceData<Object?>(
          serverId: k.serverId,
          serverName: k.serverName,
          kind: k.kind,
          value: cached.items,
          cachedAt: cached.at,
        );
        _publish();
        return false;
      }
    }
    slot.slice = SliceFailed<Object?>(
      serverId: k.serverId,
      serverName: k.serverName,
      kind: k.kind,
      error: error,
    );
    _publish();
    return false;
  }

  /// Stores the last good copy, but never for a server that is gone or no
  /// longer the active one: a delete purges the cache first and the row is
  /// removed later, so the check is made before and after the write.
  Future<void> _cacheWrite(
    _Kind k,
    DashboardCard card,
    List<MediaItem> items,
    DateTime at,
    int generation,
  ) async {
    final serverId = k.serverId;
    final cache = ref.read(dashboardCacheProvider);
    try {
      if (!await _serverExists(serverId)) return;
      if (!ref.mounted || k.generation != generation) return;
      await cache.write(serverId, card, items, at);
      if (!await _serverExists(serverId)) await cache.delete(serverId, card);
    } on Object {
      // A failed cache write only loses the offline copy.
    }
  }

  // --- state ------------------------------------------------------------------

  void _publish() {
    if (_building || !ref.mounted) return;
    final next = _compose();
    if (next != state) state = next;
  }

  DashboardSnapshot _compose() => DashboardSnapshot(
    activity: _composeCard<ActivitySummary>(
      DashboardCard.activity,
      (v) => v.isIdle,
    ),
    upcoming: _composeCard<List<MediaItem>>(
      DashboardCard.upcoming,
      (v) => v.isEmpty,
    ),
    recent: _composeCard<List<MediaItem>>(
      DashboardCard.recent,
      (v) => v.isEmpty,
    ),
  );

  CardState<T> _composeCard<T>(DashboardCard card, bool Function(T) isEmpty) {
    final raw = <CardSlice<T>>[];
    var unresolved = false;
    for (final entry in _sources.entries) {
      if (!entry.value.feeds(card)) continue;
      final k = _kinds[entry.key];
      if (k == null || !k.resolved) {
        unresolved = true;
        continue;
      }
      final slice = k.slots[card]!.slice;
      if (slice == null) continue;
      raw.add(_typed<T>(slice));
    }
    if (raw.isEmpty) {
      return unresolved ? CardLoading<T>() : CardNotConfigured<T>();
    }
    final failed = raw.whereType<SliceFailed<T>>().toList();
    if (failed.length == raw.length) return CardError<T>(failed);
    final shown = [
      for (final s in raw)
        if (!(s is SliceData<T> && isEmpty(s.value))) s,
    ];
    if (shown.isEmpty) return CardEmpty<T>();
    if (shown.every((s) => s is SliceLoading<T>)) return CardLoading<T>();
    return CardData<T>(shown);
  }

  CardSlice<T> _typed<T>(CardSlice<Object?> slice) => switch (slice) {
    SliceData<Object?>(:final value) => SliceData<T>(
      serverId: slice.serverId,
      serverName: slice.serverName,
      kind: slice.kind,
      value: value as T,
      cachedAt: slice.cachedAt,
    ),
    SliceFailed<Object?>(:final error) => SliceFailed<T>(
      serverId: slice.serverId,
      serverName: slice.serverName,
      kind: slice.kind,
      error: error,
    ),
    SliceLoading<Object?>() => SliceLoading<T>(
      serverId: slice.serverId,
      serverName: slice.serverName,
      kind: slice.kind,
    ),
  };

  // --- reporting ---------------------------------------------------------------

  void _report(
    DashboardTrigger trigger, {
    required int servers,
    required int failed,
  }) {
    ref
        .read(eventTrackerProvider)
        .track(
          DashboardRefreshedEvent(
            trigger: trigger.param,
            servers: servers,
            failed: failed,
          ),
        );
    // Counts only: no titles, names, hosts or ids.
    ref
        .read(loggerProvider)
        .info(
          'dashboard refreshed (${trigger.name}): $servers servers, $failed failed',
        );
  }

  /// Anything that is not a typed [AppError] is a bug, not an outage: it is
  /// reported as `parse_error` (never as "offline", which would show old data
  /// and hide it) and only its type is logged.
  AppError _asAppError(Object? e) {
    if (e is AppError) return e;
    if (ref.mounted) {
      ref
          .read(loggerProvider)
          .warning('dashboard unexpected error: ${e.runtimeType}');
    }
    return const AppError(
      ErrorCategory.parseError,
      debugDetail: kUnexpectedDetail,
    );
  }

  void _recordError(ServiceKind kind, AppError error) {
    final category = ErrorCategoryParam.values.where(
      (c) => c.code == error.category.code,
    );
    final service = ServiceKindParam.values.where((s) => s.code == kind.name);
    if (category.isEmpty || service.isEmpty) return;
    ref
        .read(breadcrumbsProvider)
        .add(Breadcrumb.apiError(category.first, service.first));
  }
}

DashboardCardParam _cardParam(DashboardCard card) => switch (card) {
  DashboardCard.activity => DashboardCardParam.activity,
  DashboardCard.upcoming => DashboardCardParam.upcoming,
  DashboardCard.recent => DashboardCardParam.recent,
};

/// The event parameter of [card].
DashboardCardParam dashboardCardParam(DashboardCard card) => _cardParam(card);

/// The event parameter of an item's destination.
DashboardDestinationParam dashboardDestinationParam(
  DashboardDestination destination,
) => switch (destination) {
  DashboardDestination.series => DashboardDestinationParam.series,
  DashboardDestination.movie => DashboardDestinationParam.movie,
  DashboardDestination.sonarr => DashboardDestinationParam.sonarr,
  DashboardDestination.radarr => DashboardDestinationParam.radarr,
  DashboardDestination.torrents => DashboardDestinationParam.torrents,
};
