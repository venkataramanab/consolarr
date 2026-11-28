// SPDX-License-Identifier: GPL-3.0-or-later

// Review fixes of PR #10: coalescing, unexpected errors, cache races, request
// cancellation and the failure rules of the media cards.

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/data/arr_sources.dart';
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

const _link = DashboardLink(
  '/sonarr',
  DashboardTarget.tab,
  DashboardDestination.sonarr,
);

ActivitySummary _summary(int active) =>
    ActivitySummary(active: active, attention: 0, rows: const [], link: _link);

void main() {
  late Env env;
  late FakeServer server;
  late DateTime now;

  setUp(() {
    env = Env();
    server = FakeServer();
    now = fixedNow;
  });
  tearDown(disposeContainers);

  ServerConnection conn(ServiceKind kind, String id) =>
      connection(kind, id, server);

  Future<ProviderContainer> start(
    Map<ServiceKind, DashboardSource> sources, {
    required Map<ServiceKind, Object?> connections,
    Duration deadline = const Duration(seconds: 20),
  }) async {
    env = Env(deadline: deadline, now: () => now);
    final c = env.container(sources: sources);
    c.listen(dashboardProvider, (_, _) {});
    for (final e in connections.entries) {
      c.read(activeConnections.notifier).set(e.key, e.value);
    }
    await pumpEventQueue();
    return c;
  }

  group('coalescing across a server switch', () {
    test('a late answer of the old server does not clear the new request, so '
        'no duplicate goes out', () async {
      final source = CountingSource()
        ..gates[DashboardCard.activity] = Completer();
      final oldGate = source.gates[DashboardCard.activity]!;
      final c = await start(
        {ServiceKind.sonarr: source.source},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
      );
      expect(source.calls[DashboardCard.activity], 1);
      // Switch: the new server's request is still running.
      final newGate = Completer<void>();
      source.gates[DashboardCard.activity] = newGate;
      c
          .read(activeConnections.notifier)
          .set(ServiceKind.sonarr, conn(ServiceKind.sonarr, 'b'));
      await pumpEventQueue();
      expect(source.calls[DashboardCard.activity], 2);
      // The old one finishes late...
      oldGate.complete();
      await pumpEventQueue();
      // ...and a poll must join the new request, not start a third.
      final poll = c
          .read(dashboardProvider.notifier)
          .refresh(DashboardTrigger.poll);
      await pumpEventQueue();
      expect(source.calls[DashboardCard.activity], 2, reason: 'no duplicate');
      newGate.complete();
      await poll;
      expect(source.calls[DashboardCard.activity], 2);
    });
  });

  group('unexpected errors are not "offline"', () {
    test('a StateError is a parse error: no cache, only its type is logged, '
        'never its message', () async {
      var throwing = false;
      final good = CountingSource(
        upcoming: Result.ok([
          mediaItem(
            'ep:1',
            from: conn(ServiceKind.sonarr, 'a'),
            day: DateTime.utc(2026, 3, 11),
          ),
        ]),
      ).source;
      final source = DashboardSource(
        activity: good.activity,
        upcoming: (c) async {
          if (throwing) throw StateError('Secret Title Canary');
          return good.upcoming!(c);
        },
        recent: good.recent,
      );
      final c = await start(
        {ServiceKind.sonarr: source},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
      );
      expect(snap(c).upcoming, isA<CardData<List<MediaItem>>>());
      expect(env.cache.rows, isNotEmpty, reason: 'a copy exists to be hidden');
      throwing = true;
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
      final slice = slicesOf(snap(c).upcoming).single;
      expect(slice, isA<SliceFailed<List<MediaItem>>>());
      expect((slice as SliceFailed).error.category, ErrorCategory.parseError);
      expect(env.logs.any((l) => l.contains('StateError')), isTrue);
      expect(env.logs.join(), isNot(contains('Canary')));
    });
  });

  group('credentials come through the provider seam', () {
    test(
      'SourceContext.loadCredentials reads dashboardCredentialLoader',
      () async {
        final source = DashboardSource(
          activity: (c) async {
            await c.loadCredentials();
            return Result.ok(_summary(1));
          },
        );
        await start(
          {ServiceKind.qbittorrent: source},
          connections: {
            ServiceKind.qbittorrent: conn(ServiceKind.qbittorrent, 't'),
          },
        );
        expect(env.credentialReads, ['t']);
      },
    );
  });

  group('cache rows of a deleted server', () {
    DashboardSource upcomingSource(Completer<void>? gate, ServerConnection a) {
      return DashboardSource(
        activity: (c) async => Result.ok(_summary(1)),
        upcoming: (c) async {
          if (gate != null) await gate.future;
          return Result.ok([
            mediaItem('ep:1', from: a, day: DateTime.utc(2026, 3, 11)),
          ]);
        },
      );
    }

    test('deleted while the fetch is in flight: nothing is written', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      final gate = Completer<void>();
      env = Env(now: () => now)..serverIds = {'a'};
      final c = env.container(
        sources: {ServiceKind.sonarr: upcomingSource(gate, a)},
      );
      c.listen(dashboardProvider, (_, _) {});
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, a);
      await pumpEventQueue();
      // The repository has purged the cache and removed the row; the key stream
      // has not told the dashboard yet.
      env.serverIds = <String>{};
      await env.cache.deleteForServer('a');
      gate.complete();
      await pumpEventQueue();
      expect(env.cache.rows.keys.where((k) => k.$1 == 'a'), isEmpty);
    });

    test('deleted right after the check: the row is removed again', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      env = Env(now: () => now);
      var reads = 0;
      // exists on the first look (before the write), gone on the second
      // (right after it)
      env.serverIdsLoader = () async => ++reads <= 1 ? {'a'} : <String>{};
      final c = env.container(
        sources: {ServiceKind.sonarr: upcomingSource(null, a)},
      );
      c.listen(dashboardProvider, (_, _) {});
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, a);
      await pumpEventQueue();
      expect(env.cache.rows.keys.where((k) => k.$1 == 'a'), isEmpty);
    });

    test('a connection change after the delete drops the rows', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      env = Env(now: () => now)..serverIds = {'a'};
      final c = env.container(
        sources: {ServiceKind.sonarr: upcomingSource(null, a)},
      );
      c.listen(dashboardProvider, (_, _) {});
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, a);
      await pumpEventQueue();
      expect(env.cache.rows.keys.where((k) => k.$1 == 'a'), isNotEmpty);
      env.serverIds = <String>{};
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, null);
      await pumpEventQueue();
      expect(env.cache.rows.keys.where((k) => k.$1 == 'a'), isEmpty);
    });

    test('a switch to another server keeps the first one\'s rows', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      env = Env(now: () => now)..serverIds = {'a', 'b'};
      final c = env.container(
        sources: {ServiceKind.sonarr: upcomingSource(null, a)},
      );
      c.listen(dashboardProvider, (_, _) {});
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, a);
      await pumpEventQueue();
      c
          .read(activeConnections.notifier)
          .set(ServiceKind.sonarr, conn(ServiceKind.sonarr, 'b'));
      await pumpEventQueue();
      expect(env.cache.rows.keys.where((k) => k.$1 == 'a'), isNotEmpty);
    });

    test('rows of servers that no longer exist are pruned once, after the '
        'first frame, and only the dashboard\'s own', () async {
      env = Env(now: () => now)..serverIds = {'b'};
      final stamp = DateTime.utc(2026, 3, 1);
      await env.cache.write('gone', 'dashboard.upcoming', '{}', stamp);
      await env.cache.write('gone', 'dashboard.recent', '{}', stamp);
      await env.cache.write('gone', 'sonarr.series', '{}', stamp);
      await env.cache.write('b', 'dashboard.upcoming', '{}', stamp);
      var reads = 0;
      env.serverIdsLoader = () async {
        reads++;
        return {'b'};
      };
      final before = env.container(
        firstFrameDone: false,
        sources: {ServiceKind.sonarr: CountingSource().source},
      );
      before.listen(dashboardProvider, (_, _) {});
      await pumpEventQueue();
      expect(reads, 0, reason: 'no I/O before the first frame');
      expect(env.cache.rows.length, 4);

      final c = env.container(
        sources: {ServiceKind.sonarr: CountingSource().source},
      );
      c.listen(dashboardProvider, (_, _) {});
      await pumpEventQueue();
      expect(env.cache.rows.keys.toSet(), {
        ('gone', 'sonarr.series'),
        ('b', 'dashboard.upcoming'),
      });
    });
  });

  group('requests are cancelled', () {
    Future<ProviderContainer> hung({
      Duration deadline = const Duration(milliseconds: 30),
    }) async {
      server.gate = Completer<void>(); // nobody answers
      return start(
        {ServiceKind.sonarr: sonarrDashboardSource},
        connections: {ServiceKind.sonarr: conn(ServiceKind.sonarr, 'a')},
        deadline: deadline,
      );
    }

    test(
      'a deadline closes the request: polls never stack connections',
      () async {
        final c = await hung();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final n = c.read(dashboardProvider.notifier);
        for (var i = 0; i < 4; i++) {
          await n.refresh(DashboardTrigger.poll);
          await pumpEventQueue();
          expect(server.inFlight, 0, reason: 'poll $i');
        }
        expect(server.maxInFlight, lessThanOrEqualTo(3));
        expect(server.cancelledRequests, server.requests.length);
      },
    );

    test('a connection change cancels what the old server was asked', () async {
      final c = await hung(deadline: const Duration(seconds: 20));
      await pumpEventQueue();
      expect(server.inFlight, 3);
      c.read(activeConnections.notifier).set(ServiceKind.sonarr, null);
      await pumpEventQueue();
      expect(server.inFlight, 0);
      expect(server.cancelledRequests, 3);
    });

    test('dispose cancels what is on the wire', () async {
      final c = await hung(deadline: const Duration(seconds: 20));
      await pumpEventQueue();
      expect(server.inFlight, 3);
      c.dispose();
      await pumpEventQueue();
      expect(server.inFlight, 0);
    });

    test('the cancel token never reaches the artwork Dio', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      server.routes['calendar'] = (_) => jsonBody([
        episodeJson(id: 1, seriesId: 1, airDateUtc: '2026-03-11T12:00:00Z'),
      ]);
      final c = await start(
        {ServiceKind.sonarr: sonarrDashboardSource},
        connections: {ServiceKind.sonarr: a},
      );
      final slice =
          slicesOf(snap(c).upcoming).single as SliceData<List<MediaItem>>;
      expect(slice.value.single.dio, same(a.dio));
    });
  });

  group('media cards survive a single blip', () {
    late CountingSource source;
    late ProviderContainer c;
    late ServerConnection a;

    setUp(() async {
      a = conn(ServiceKind.sonarr, 'a');
      source = CountingSource(
        upcoming: Result.ok([
          mediaItem('ep:1', from: a, day: DateTime.utc(2026, 3, 11)),
        ]),
        recent: Result.ok([mediaItem('hist:1', from: a, at: fixedNow)]),
      );
      c = await start(
        {ServiceKind.sonarr: source.source},
        connections: {ServiceKind.sonarr: a},
      );
    });

    Future<void> stalePoll() async {
      now = now.add(const Duration(minutes: 6));
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.poll);
    }

    test('one failed poll keeps the carousel; the second marks it', () async {
      source.upcoming = const Result.err(AppError(ErrorCategory.timeout));
      env.cache.rows.clear();
      await stalePoll();
      var slice = slicesOf(snap(c).upcoming).single;
      expect(slice, isA<SliceData<List<MediaItem>>>());
      expect((slice as SliceData).cachedAt, isNull);
      await stalePoll();
      slice = slicesOf(snap(c).upcoming).single;
      expect(slice, isA<SliceFailed<List<MediaItem>>>());
    });

    test('a user pull reports a failure at once', () async {
      source.upcoming = const Result.err(AppError(ErrorCategory.timeout));
      env.cache.rows.clear();
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
      expect(snap(c).upcoming, isA<CardError<List<MediaItem>>>());
    });

    test('a pull that joins a running poll is reported as a pull', () async {
      source.upcoming = const Result.err(AppError(ErrorCategory.timeout));
      env.cache.rows.clear();
      final gate = Completer<void>();
      source.gates[DashboardCard.upcoming] = gate;
      now = now.add(const Duration(minutes: 6));
      final n = c.read(dashboardProvider.notifier);
      final poll = n.refresh(DashboardTrigger.poll);
      await pumpEventQueue();
      final pull = n.refresh(DashboardTrigger.pull);
      await pumpEventQueue();
      gate.complete();
      await Future.wait([poll, pull]);
      expect(snap(c).upcoming, isA<CardError<List<MediaItem>>>());
      expect(source.calls[DashboardCard.upcoming], 2, reason: 'one request');
    });
  });

  group('a failed media slice backs off', () {
    test('it is not asked every poll; the wait grows', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      final source = CountingSource(
        upcoming: const Result.err(AppError(ErrorCategory.serverError)),
      );
      final c = await start(
        {ServiceKind.sonarr: source.source},
        connections: {ServiceKind.sonarr: a},
      );
      final n = c.read(dashboardProvider.notifier);
      expect(source.calls[DashboardCard.upcoming], 1);
      now = now.add(const Duration(seconds: 15));
      await n.refresh(DashboardTrigger.poll);
      expect(source.calls[DashboardCard.upcoming], 1, reason: '15 s: too soon');
      now = now.add(const Duration(seconds: 16)); // 31 s since the attempt
      await n.refresh(DashboardTrigger.poll);
      expect(source.calls[DashboardCard.upcoming], 2);
      now = now.add(const Duration(seconds: 31)); // the wait is 60 s now
      await n.refresh(DashboardTrigger.poll);
      expect(source.calls[DashboardCard.upcoming], 2);
      now = now.add(const Duration(seconds: 30));
      await n.refresh(DashboardTrigger.poll);
      expect(source.calls[DashboardCard.upcoming], 3);
    });
  });

  group('cached items of a day that has passed', () {
    test('are dropped when the cache is served', () async {
      final a = conn(ServiceKind.sonarr, 'a');
      final source = CountingSource(
        upcoming: Result.ok([
          mediaItem(
            'ep:old',
            title: 'Yesterday',
            from: a,
            day: DateTime.utc(2026, 3, 9),
          ),
          mediaItem(
            'ep:new',
            title: 'Tomorrow',
            from: a,
            day: DateTime.utc(2026, 3, 11),
          ),
        ]),
      );
      final c = await start(
        {ServiceKind.sonarr: source.source},
        connections: {ServiceKind.sonarr: a},
      );
      source.upcoming = const Result.err(AppError(ErrorCategory.timeout));
      await c.read(dashboardProvider.notifier).refresh(DashboardTrigger.pull);
      final slice =
          slicesOf(snap(c).upcoming).single as SliceData<List<MediaItem>>;
      expect(slice.value.map((i) => i.id), ['ep:new']);
      expect(slice.cachedAt, isNotNull);
    });
  });
}
