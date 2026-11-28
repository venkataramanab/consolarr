// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

DashboardSnapshot snap(ProviderContainer c) => c.read(dashboardProvider);

List<CardSlice<T>> slicesOf<T>(CardState<T> s) => switch (s) {
  CardData<T>(:final slices) => slices,
  CardError<T>(:final slices) => slices,
  _ => const [],
};

void main() {
  late Env env;
  late FakeServer server;

  setUp(() {
    env = Env();
    server = FakeServer();
  });
  tearDown(disposeContainers);

  Future<ProviderContainer> start(
    Map<ServiceKind, CountingSource> sources, {
    Map<ServiceKind, Object?> connections = const {},
    Duration? deadline,
    DateTime Function()? now,
  }) async {
    env = Env(deadline: deadline ?? const Duration(seconds: 20), now: now);
    final c = env.container(
      sources: {for (final e in sources.entries) e.key: e.value.source},
    );
    c.listen(dashboardProvider, (_, _) {});
    for (final k in sources.keys) {
      c.read(activeConnections.notifier).set(k, connections[k]);
    }
    for (final e in connections.entries) {
      c.read(activeConnections.notifier).set(e.key, e.value);
    }
    await pumpEventQueue();
    return c;
  }

  ServerConnection conn(ServiceKind kind, String id, {String? name}) =>
      connection(kind, id, server, name: name);

  group('before the first frame', () {
    test('no source runs and no connection is read', () async {
      final source = CountingSource();
      var connectionReads = 0;
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...env.overrides(
            firstFrameDone: false,
            sources: {ServiceKind.sonarr: source.source},
          ),
        ],
      );
      addTearDownContainer(c);
      c.listen(dashboardProvider, (_, _) {});
      c
          .read(activeConnections.notifier)
          .set(ServiceKind.sonarr, conn(ServiceKind.sonarr, 'a'));
      await pumpEventQueue();
      expect(snap(c), const DashboardSnapshot());
      expect(source.calls.values.every((n) => n == 0), isTrue);
      expect(connectionReads, 0);
    });
  });

  group('card states', () {
    test('nothing configured: every card is not configured', () async {
      final c = await start({
        ServiceKind.sonarr: CountingSource(),
        ServiceKind.qbittorrent: CountingSource(feedsMedia: false),
      });
      expect(snap(c).activity, isA<CardNotConfigured<ActivitySummary>>());
      expect(snap(c).upcoming, isA<CardNotConfigured<List<MediaItem>>>());
      expect(snap(c).recent, isA<CardNotConfigured<List<MediaItem>>>());
    });

    test('still resolving the connection: loading', () async {
      final pending = Completer<ServerConnection?>();
      final c = await start(
        {ServiceKind.sonarr: CountingSource()},
        connections: {ServiceKind.sonarr: pending},
      );
      expect(snap(c).activity, isA<CardLoading<ActivitySummary>>());
      pending.complete(null);
      await pumpEventQueue();
      expect(snap(c).activity, isA<CardNotConfigured<ActivitySummary>>());
    });

    test('only a torrent client: activity data, the media cards say '
        'not configured', () async {
      final c = await start(
        {
          ServiceKind.sonarr: CountingSource(),
          ServiceKind.qbittorrent: CountingSource(feedsMedia: false),
        },
        connections: {
          ServiceKind.qbittorrent: conn(ServiceKind.qbittorrent, 't'),
        },
      );
      expect(snap(c).activity, isA<CardData<ActivitySummary>>());
      expect(snap(c).upcoming, isA<CardNotConfigured<List<MediaItem>>>());
      expect(snap(c).recent, isA<CardNotConfigured<List<MediaItem>>>());
    });

    test(
      'empty answers: "nothing" is not "all good" and not an error',
      () async {
        final idle = CountingSource(
          activity: const Result.ok(
            ActivitySummary(
              active: 0,
              attention: 0,
              rows: [],
              link: DashboardLink(
                '/sonarr',
                DashboardTarget.tab,
                DashboardDestination.sonarr,
              ),
            ),
          ),
        );
        final c = await start(
          {ServiceKind.sonarr: idle},
          connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        );
        expect(snap(c).activity, isA<CardEmpty<ActivitySummary>>());
        expect(snap(c).upcoming, isA<CardEmpty<List<MediaItem>>>());
        expect(snap(c).recent, isA<CardEmpty<List<MediaItem>>>());
      },
    );

    test('data carries the server id, name and kind of its slice', () async {
      final a = conn(ServiceKind.sonarr, 'a', name: 'Living room');
      final c = await start(
        {ServiceKind.sonarr: CountingSource()},
        connections: {ServiceKind.sonarr: a},
      );
      final slice = slicesOf(snap(c).activity).single;
      expect(slice.serverId, 'a');
      expect(slice.serverName, 'Living room');
      expect(slice.kind, ServiceKind.sonarr);
    });
  });

  group('partial results and per-server isolation', () {
    test(
      'one failing kind beside healthy ones marks only its own slice',
      () async {
        final sonarr = CountingSource();
        final radarr = CountingSource(
          activity: const Result.err(AppError(ErrorCategory.authFailed)),
        );
        final torrent = CountingSource(feedsMedia: false);
        final c = await start(
          {
            ServiceKind.sonarr: sonarr,
            ServiceKind.radarr: radarr,
            ServiceKind.qbittorrent: torrent,
          },
          connections: {
            ServiceKind.sonarr: conn(ServiceKind.sonarr, 's'),
            ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
            ServiceKind.qbittorrent: conn(ServiceKind.qbittorrent, 't'),
          },
        );
        final slices = slicesOf(snap(c).activity);
        expect(snap(c).activity, isA<CardData<ActivitySummary>>());
        expect(slices, hasLength(3));
        final failed = slices.whereType<SliceFailed<ActivitySummary>>().single;
        expect(failed.kind, ServiceKind.radarr);
        expect(failed.error.category, ErrorCategory.authFailed);
        expect(slices.whereType<SliceData<ActivitySummary>>(), hasLength(2));
      },
    );

    test('every server failing is a card error with one slice each', () async {
      const err = Result<ActivitySummary>.err(
        AppError(ErrorCategory.serverError),
      );
      final c = await start(
        {
          ServiceKind.sonarr: CountingSource(activity: err),
          ServiceKind.radarr: CountingSource(activity: err),
        },
        connections: {
          ServiceKind.sonarr: conn(ServiceKind.sonarr, 's'),
          ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
        },
      );
      final state = snap(c).activity as CardError<ActivitySummary>;
      expect(state.slices.map((s) => s.kind).toSet(), {
        ServiceKind.sonarr,
        ServiceKind.radarr,
      });
    });

    test('a connection that fails (missing credentials) names its server and '
        'leaves the others alone', () async {
      final c = await start(
        {
          ServiceKind.sonarr: CountingSource(),
          ServiceKind.radarr: CountingSource(),
        },
        connections: {
          ServiceKind.sonarr: const AppError(
            ErrorCategory.authFailed,
            debugDetail: 'needs_credentials',
          ),
          ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
        },
      );
      // The slice names the service at once and the server once the list
      // answered.
      await pumpEventQueue();
      final slices = slicesOf(snap(c).activity);
      final failed = slices.whereType<SliceFailed<ActivitySummary>>().single;
      expect(failed.kind, ServiceKind.sonarr);
      expect(failed.serverId, 'failed-sonarr');
      expect(failed.serverName, 'Server one');
      expect(
        slices.whereType<SliceData<ActivitySummary>>().single.kind,
        ServiceKind.radarr,
      );
    });

    test(
      'a hung server hits its deadline and never delays the others',
      () async {
        final hung = CountingSource()
          ..gates[DashboardCard.activity] = Completer();
        final c = await start(
          {ServiceKind.sonarr: hung, ServiceKind.radarr: CountingSource()},
          connections: {
            ServiceKind.sonarr: conn(ServiceKind.sonarr, 's'),
            ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
          },
          deadline: const Duration(milliseconds: 60),
        );
        // The healthy server answered at once; the hung one is still loading.
        var slices = slicesOf(snap(c).activity);
        expect(
          slices.whereType<SliceData<ActivitySummary>>().single.kind,
          ServiceKind.radarr,
        );
        expect(
          slices.whereType<SliceLoading<ActivitySummary>>().single.kind,
          ServiceKind.sonarr,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        slices = slicesOf(snap(c).activity);
        final failed = slices.whereType<SliceFailed<ActivitySummary>>().single;
        expect(failed.error.category, ErrorCategory.timeout);
        expect(
          slices.whereType<SliceData<ActivitySummary>>().single.kind,
          ServiceKind.radarr,
        );
      },
    );

    test('slices update as each server answers, not all at the end', () async {
      final slow = CountingSource()
        ..gates[DashboardCard.activity] = Completer();
      final c = await start(
        {ServiceKind.sonarr: slow, ServiceKind.radarr: CountingSource()},
        connections: {
          ServiceKind.sonarr: conn(ServiceKind.sonarr, 's'),
          ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
        },
      );
      expect(
        slicesOf(snap(c).activity).whereType<SliceData<ActivitySummary>>(),
        hasLength(1),
      );
      slow.gates[DashboardCard.activity]!.complete();
      await pumpEventQueue();
      expect(
        slicesOf(snap(c).activity).whereType<SliceData<ActivitySummary>>(),
        hasLength(2),
      );
    });
  });

  group('server switch and deletion mid-load', () {
    test('a late answer of the previous server is dropped', () async {
      final source = CountingSource()
        ..gates[DashboardCard.activity] = Completer();
      final a = conn(ServiceKind.sonarr, 'a');
      final b = conn(ServiceKind.sonarr, 'b');
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: a},
      );
      expect(snap(c).activity, isA<CardLoading<ActivitySummary>>());
      // Switch while A is still loading; B answers at once.
      final oldGate = source.gates[DashboardCard.activity]!;
      source.gates[DashboardCard.activity] = null;
      source.activity = const Result.ok(
        ActivitySummary(
          active: 7,
          attention: 0,
          rows: [],
          link: DashboardLink(
            '/sonarr',
            DashboardTarget.tab,
            DashboardDestination.sonarr,
          ),
        ),
      );
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, b);
      await pumpEventQueue();
      var slice =
          slicesOf(snap(c).activity).single as SliceData<ActivitySummary>;
      expect(slice.serverId, 'b');
      expect(slice.value.active, 7);
      // A finally answers (with other data): nothing changes.
      source.activity = const Result.ok(
        ActivitySummary(
          active: 1,
          attention: 0,
          rows: [],
          link: DashboardLink(
            '/sonarr',
            DashboardTarget.tab,
            DashboardDestination.sonarr,
          ),
        ),
      );
      oldGate.complete();
      await pumpEventQueue();
      slice = slicesOf(snap(c).activity).single as SliceData<ActivitySummary>;
      expect(slice.serverId, 'b');
      expect(slice.value.active, 7);
    });

    test(
      'deleting the active server mid-load ends in "not configured"',
      () async {
        final source = CountingSource()
          ..gates[DashboardCard.activity] = Completer();
        final c = await start(
          {ServiceKind.sonarr: source},
          connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        );
        c.read(activeConnections.notifier).set(ServiceKind.sonarr, null);
        await pumpEventQueue();
        source.gates[DashboardCard.activity]!.complete();
        await pumpEventQueue();
        expect(snap(c).activity, isA<CardNotConfigured<ActivitySummary>>());
      },
    );

    test('a switch of one kind leaves the other kinds untouched', () async {
      final sonarr = CountingSource();
      final radarr = CountingSource();
      final c = await start(
        {ServiceKind.sonarr: sonarr, ServiceKind.radarr: radarr},
        connections: {
          ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a'),
          ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
        },
      );
      final radarrCalls = Map.of(radarr.calls);
      c
          .read(activeConnections.notifier)
          .set(ServiceKind.sonarr, conn(ServiceKind.sonarr, 'b'));
      await pumpEventQueue();
      expect(radarr.calls, radarrCalls, reason: 'radarr was not refetched');
      final ids = slicesOf(snap(c).activity).map((s) => s.serverId).toSet();
      expect(ids, {'b', 'r'});
    });

    test('the cache of one server is never shown for another', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      final b = conn(ServiceKind.sonarr, 'b');
      final good = CountingSource(
        upcoming: Result.ok([
          mediaItem(
            'ep:1',
            title: 'Only On Server A',
            from: a,
            day: DateTime.utc(2026, 3, 11),
          ),
        ]),
      );
      final c = await start(
        {ServiceKind.sonarr: good},
        connections: {ServiceKind.sonarr: a},
      );
      expect(snap(c).upcoming, isA<CardData<List<MediaItem>>>());
      good.upcoming = const Result.err(AppError(ErrorCategory.timeout));
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, b);
      await pumpEventQueue();
      expect(snap(c).upcoming, isA<CardError<List<MediaItem>>>());
    });
  });

  group('refresh', () {
    test('overlapping refreshes coalesce into one request per card', () async {
      final source = CountingSource();
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
      );
      final before = Map.of(source.calls);
      source.gates[DashboardCard.activity] = Completer();
      final n = c.read(dashboardProvider.notifier);
      final first = n.refresh(DashboardTrigger.pull);
      final second = n.refresh(DashboardTrigger.pull);
      final third = n.refresh(DashboardTrigger.poll);
      await pumpEventQueue();
      source.gates[DashboardCard.activity]!.complete();
      await Future.wait([first, second, third]);
      for (final card in DashboardCard.values) {
        expect(source.calls[card]! - before[card]!, 1, reason: '$card');
      }
    });

    test(
      'a refresh while the connection is still resolving is ignored',
      () async {
        final pending = Completer<ServerConnection?>();
        final source = CountingSource();
        final c = await start(
          {ServiceKind.sonarr: source},
          connections: {ServiceKind.sonarr: pending},
        );
        await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
        expect(source.calls.values.every((n) => n == 0), isTrue);
      },
    );

    test(
      'pull and resume refresh all three cards, retry only its card',
      () async {
        final source = CountingSource();
        final c = await start(
          {ServiceKind.sonarr: source},
          connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        );
        final n = c.read(dashboardProvider.notifier);
        await n.refresh(DashboardTrigger.pull);
        await n.refresh(DashboardTrigger.resume);
        expect(source.calls.values, everyElement(3));
      },
    );

    test('a poll refreshes the activity only, until upcoming and recent are '
        'five minutes old', () async {
      var now = fixedNow;
      final source = CountingSource();
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        now: () => now,
      );
      final n = c.read(dashboardProvider.notifier);
      now = fixedNow.add(const Duration(minutes: 4, seconds: 59));
      await n.refresh(DashboardTrigger.poll);
      expect(source.calls[DashboardCard.activity], 2);
      expect(source.calls[DashboardCard.upcoming], 1);
      expect(source.calls[DashboardCard.recent], 1);
      now = fixedNow.add(const Duration(minutes: 5));
      await n.refresh(DashboardTrigger.poll);
      expect(source.calls[DashboardCard.activity], 3);
      expect(source.calls[DashboardCard.upcoming], 2);
      expect(source.calls[DashboardCard.recent], 2);
    });

    test('an unchanged poll publishes nothing (no card rebuilds)', () async {
      final source = CountingSource();
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
      );
      var changes = 0;
      c.listen(dashboardProvider, (_, _) => changes++);
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.poll);
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.poll);
      expect(changes, 0);
    });

    test(
      'a changed activity publishes, and the other cards stay equal',
      () async {
        final source = CountingSource();
        final c = await start(
          {ServiceKind.sonarr: source},
          connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        );
        final before = snap(c);
        source.activity = const Result.ok(
          ActivitySummary(
            active: 9,
            attention: 0,
            rows: [],
            link: DashboardLink(
              '/sonarr',
              DashboardTarget.tab,
              DashboardDestination.sonarr,
            ),
          ),
        );
        await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.poll);
        final after = snap(c);
        expect(after.activity, isNot(before.activity));
        expect(after.upcoming, before.upcoming);
        expect(after.recent, before.recent);
      },
    );

    test(
      'concurrency: one request per kind and card, never more at once',
      () async {
        final sources = {
          ServiceKind.sonarr: CountingSource(),
          ServiceKind.radarr: CountingSource(),
          ServiceKind.qbittorrent: CountingSource(feedsMedia: false),
          ServiceKind.transmission: CountingSource(feedsMedia: false),
          ServiceKind.deluge: CountingSource(feedsMedia: false),
        };
        for (final s in sources.values) {
          s.gates[DashboardCard.activity] = Completer();
        }
        final c = await start(
          sources,
          connections: {
            for (final k in sources.keys) k: conn(k, 'id-${k.name}'),
          },
        );
        final n = c.read(dashboardProvider.notifier);
        final refreshing = n.refresh(DashboardTrigger.pull);
        await pumpEventQueue();
        for (final e in sources.entries) {
          expect(e.value.maxInFlight, lessThanOrEqualTo(3), reason: '${e.key}');
          expect(e.value.calls[DashboardCard.activity], 1);
        }
        for (final s in sources.values) {
          s.gates[DashboardCard.activity]!.complete();
        }
        await refreshing;
        // The pull joined the activity request of the first load; upcoming and
        // recent were asked once more.
        final sonarr = sources[ServiceKind.sonarr]!;
        expect(sonarr.calls[DashboardCard.activity], 1);
        expect(sonarr.calls[DashboardCard.upcoming], 2);
        expect(sonarr.calls[DashboardCard.recent], 2);
        expect(sources[ServiceKind.deluge]!.calls[DashboardCard.upcoming], 0);
      },
    );

    test(
      'a poll that fails everywhere reports false so the scheduler backs off',
      () async {
        final source = CountingSource();
        final c = await start(
          {ServiceKind.sonarr: source},
          connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        );
        source.activity = const Result.err(AppError(ErrorCategory.timeout));
        final n = c.read(dashboardProvider.notifier);
        expect(await n.refresh(DashboardTrigger.poll), isFalse);
        expect(await n.refresh(DashboardTrigger.poll), isFalse);
        expect(await n.refresh(DashboardTrigger.poll), isFalse);
      },
    );
  });

  group('failures keep what is on screen as long as they may', () {
    test('a transient poll failure keeps the activity; the third shows it; '
        'a pull reports at once', () async {
      final source = CountingSource();
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
      );
      final n = c.read(dashboardProvider.notifier);
      source.activity = const Result.err(AppError(ErrorCategory.timeout));
      await n.refresh(DashboardTrigger.poll);
      await n.refresh(DashboardTrigger.poll);
      expect(
        slicesOf(snap(c).activity).single,
        isA<SliceData<ActivitySummary>>(),
      );
      await n.refresh(DashboardTrigger.poll);
      expect(snap(c).activity, isA<CardError<ActivitySummary>>());

      source.activity = const Result.ok(
        ActivitySummary(
          active: 2,
          attention: 0,
          rows: [],
          link: DashboardLink(
            '/sonarr',
            DashboardTarget.tab,
            DashboardDestination.sonarr,
          ),
        ),
      );
      await n.refresh(DashboardTrigger.pull);
      expect(snap(c).activity, isA<CardData<ActivitySummary>>());
      source.activity = const Result.err(AppError(ErrorCategory.timeout));
      await n.refresh(DashboardTrigger.pull);
      expect(snap(c).activity, isA<CardError<ActivitySummary>>());
    });
  });

  group('offline copy of upcoming and recent', () {
    late ServerConnection a;
    late CountingSource source;
    late ProviderContainer c;

    setUp(() async {
      a = conn(ServiceKind.sonarr, 'a');
      source = CountingSource(
        upcoming: Result.ok([
          mediaItem(
            'ep:1',
            title: 'Cached Show',
            from: a,
            day: DateTime.utc(2026, 3, 11),
            season: 1,
            episode: 2,
          ),
        ]),
        recent: Result.ok([mediaItem('hist:1', from: a, at: fixedNow)]),
      );
      c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: a},
      );
    });

    for (final category in kOfflineFallbackCategories) {
      test(
        '${category.code}: the last good copy is shown with its age',
        () async {
          source.upcoming = Result.err(AppError(category));
          await c
              .read(dashboardProvider.notifier)
              .refresh(DashboardTrigger.pull);
          final slice =
              slicesOf(snap(c).upcoming).single as SliceData<List<MediaItem>>;
          expect(slice.cachedAt, fixedNow);
          expect(slice.value.single.title, 'Cached Show');
          expect(
            slice.value.single.dio,
            same(a.dio),
            reason: 'the cached rows use the current connection',
          );
          expect(slice.value.single.season, 1);
        },
      );
    }

    for (final category in [
      ErrorCategory.authFailed,
      ErrorCategory.unsupportedVersion,
      ErrorCategory.tlsUntrusted,
      ErrorCategory.tlsPinMismatch,
      ErrorCategory.tlsExpired,
      ErrorCategory.cleartextRefused,
    ]) {
      test('${category.code}: never hidden behind old data', () async {
        source.upcoming = Result.err(AppError(category));
        await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
        expect(snap(c).upcoming, isA<CardError<List<MediaItem>>>());
      });
    }

    test('the activity is live: never cached', () async {
      source.activity = const Result.err(AppError(ErrorCategory.timeout));
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
      expect(snap(c).activity, isA<CardError<ActivitySummary>>());
      expect(
        env.cache.rows.keys.map((k) => k.$2),
        everyElement(isNot(contains('activity'))),
      );
    });

    test('no cached copy: the failure is shown', () async {
      env.cache.rows.clear();
      source.upcoming = const Result.err(AppError(ErrorCategory.timeout));
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
      expect(snap(c).upcoming, isA<CardError<List<MediaItem>>>());
    });

    test('rows are keyed by server and card', () {
      expect(env.cache.rows.keys.toSet(), {
        ('a', 'dashboard.upcoming'),
        ('a', 'dashboard.recent'),
      });
    });
  });

  group('retry', () {
    test(
      'retries only the failed servers of a card and reports the category',
      () async {
        final bad = CountingSource(
          activity: const Result.err(AppError(ErrorCategory.serverError)),
        );
        final good = CountingSource();
        final c = await start(
          {ServiceKind.sonarr: bad, ServiceKind.radarr: good},
          connections: {
            ServiceKind.sonarr: conn(ServiceKind.sonarr, 's'),
            ServiceKind.radarr: conn(ServiceKind.radarr, 'r'),
          },
        );
        final goodCalls = good.calls[DashboardCard.activity];
        bad.activity = Result.ok(
          const ActivitySummary(
            active: 3,
            attention: 0,
            rows: [],
            link: DashboardLink(
              '/sonarr',
              DashboardTarget.tab,
              DashboardDestination.sonarr,
            ),
          ),
        );
        await c.read(dashboardProvider.notifier).retry(DashboardCard.activity);
        expect(good.calls[DashboardCard.activity], goodCalls);
        expect(
          slicesOf(snap(c).activity).whereType<SliceFailed<ActivitySummary>>(),
          isEmpty,
        );
        final retried = env.analytics.events.where(
          (e) => e.name == 'dashboard_card_retried',
        );
        expect(retried.single.parameters, {
          'card': 'activity',
          'error_category': 'server_error',
        });
      },
    );
  });

  group('no leak', () {
    test('titles, names, hosts and ids never reach an event, a breadcrumb or '
        'a log', () async {
      final a = conn(ServiceKind.sonarr, 'secret-id-1', name: 'Secret Name');
      final source = CountingSource(
        activity: const Result.err(AppError(ErrorCategory.authFailed)),
        upcoming: Result.ok([
          mediaItem(
            'ep:1',
            title: 'Secret Title',
            from: a,
            day: DateTime.utc(2026, 3, 11),
          ),
        ]),
      );
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: a},
      );
      final n = c.read(dashboardProvider.notifier);
      await n.refresh(DashboardTrigger.pull);
      await n.retry(DashboardCard.activity);
      final seen = [
        for (final e in env.analytics.events) '${e.name} ${e.parameters}',
        for (final b in env.breadcrumbs.entries) b.line,
        ...env.logs,
      ].join('\n');
      expect(env.analytics.events, isNotEmpty);
      expect(env.logs, isNotEmpty);
      for (final secret in [
        'Secret Title',
        'Secret Name',
        'secret-id-1',
        'example',
        'https',
      ]) {
        expect(seen, isNot(contains(secret)));
      }
      final refreshed = env.analytics.events.firstWhere(
        (e) => e.name == 'dashboard_refreshed',
      );
      expect(refreshed.parameters.keys, {'trigger', 'servers', 'failed'});
      expect(refreshed.parameters['servers'], 1);
    });
  });
}
