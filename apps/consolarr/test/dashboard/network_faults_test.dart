// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/application/dashboard_sources.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

/// The real Sonarr and Radarr sources over a server with injected faults.
FakeServer healthyArr() => FakeServer({
  'calendar': (o) => jsonBody([
    episodeJson(id: 1, seriesId: 1, airDateUtc: '2026-03-11T10:00:00Z'),
  ]),
  'queue': (_) => jsonBody(page([queueJson(id: 1, series: 'Example Show')])),
  'history': (_) => jsonBody(page([historyRowJson(id: 1, seriesId: 1)])),
});

ServerConnection faulty(
  ServiceKind kind,
  String id,
  FakeServer inner,
  List<Fault> faults,
  List<FaultInjectingAdapter> adapters,
) {
  final c = connection(kind, id, inner);
  final adapter = FaultInjectingAdapter(inner: inner, faults: faults);
  adapters.add(adapter);
  c.dio.httpClientAdapter = adapter;
  return ServerConnection(profile: c.profile, dio: c.dio);
}

List<CardSlice<T>> slices<T>(CardState<T> s) => switch (s) {
  CardData<T>(:final slices) => slices,
  CardError<T>(:final slices) => slices,
  _ => const [],
};

void main() {
  tearDown(disposeContainers);

  Future<(ProviderContainer, Env)> start(
    Map<ServiceKind, ServerConnection> connections, {
    Duration deadline = const Duration(seconds: 20),
    bool settle = true,
  }) async {
    final env = Env(deadline: deadline);
    final c = env.container(sources: dashboardSources);
    c.listen(dashboardProvider, (_, _) {});
    for (final e in connections.entries) {
      c.read(activeConnections.notifier).set(e.key, e.value);
    }
    if (settle) await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue(times: settle ? 200 : 10);
    return (c, env);
  }

  test('a dropped connection fails only its own server', () async {
    final adapters = <FaultInjectingAdapter>[];
    final (c, env) = await start({
      ServiceKind.sonarr: faulty(ServiceKind.sonarr, 's', healthyArr(), const [
        ConnectionDropFault(),
      ], adapters),
      ServiceKind.radarr: connection(
        ServiceKind.radarr,
        'r',
        FakeServer({
          'calendar': (_) => jsonBody([
            movieJson(id: 1, digitalRelease: '2026-03-12T00:00:00Z'),
          ]),
          'queue': (_) => jsonBody(page([queueJson(id: 1, movieId: 1)])),
          'history': (_) => jsonBody(page([historyRowJson(id: 1, movieId: 1)])),
        }),
      ),
    });
    final state = c.read(dashboardProvider);
    for (final card in [state.activity, state.upcoming, state.recent]) {
      final list = slices<Object?>(card as CardState<Object?>);
      expect(
        list.whereType<SliceFailed<Object?>>().single.kind,
        ServiceKind.sonarr,
      );
      expect(
        list.whereType<SliceFailed<Object?>>().single.error.category,
        ErrorCategory.networkUnreachable,
      );
      expect(
        list.whereType<SliceData<Object?>>().single.kind,
        ServiceKind.radarr,
      );
    }
    expect(env.logs.join(), isNot(contains('Example Show')));
  });

  test(
    'a timeout is a timeout, with one request per card (no blind retry)',
    () async {
      final adapters = <FaultInjectingAdapter>[];
      final (c, _) = await start({
        ServiceKind.sonarr: faulty(
          ServiceKind.sonarr,
          's',
          healthyArr(),
          const [TimeoutFault()],
          adapters,
        ),
      });
      final failed = slices<ActivitySummary>(c.read(dashboardProvider).activity)
          .whereType<SliceFailed<ActivitySummary>>()
          .single;
      expect(failed.error.category, ErrorCategory.timeout);
      expect(adapters.single.requestCount, 3, reason: 'one per card');
    },
  );

  test(
    'a slow server hits the deadline while a healthy one is not delayed',
    () async {
      final adapters = <FaultInjectingAdapter>[];
      final (c, _) = await start({
        ServiceKind.sonarr: faulty(
          ServiceKind.sonarr,
          's',
          healthyArr(),
          const [LatencyFault(Duration(seconds: 30))],
          adapters,
        ),
        ServiceKind.radarr: connection(
          ServiceKind.radarr,
          'r',
          FakeServer({
            'queue': (_) => jsonBody(page([queueJson(id: 1, movieId: 1)])),
            'calendar': (_) => jsonBody([]),
            'history': (_) => jsonBody(page([])),
          }),
        ),
      }, deadline: const Duration(milliseconds: 150));
      var activity = slices<ActivitySummary>(
        c.read(dashboardProvider).activity,
      );
      expect(
        activity.whereType<SliceLoading<ActivitySummary>>().single.kind,
        ServiceKind.sonarr,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await pumpEventQueue();
      activity = slices<ActivitySummary>(c.read(dashboardProvider).activity);
      expect(
        activity
            .whereType<SliceFailed<ActivitySummary>>()
            .single
            .error
            .category,
        ErrorCategory.timeout,
      );
    },
  );

  test('a body that drops halfway is a failure, never half a list', () async {
    final server = FakeServer({
      'history': (_) => ResponseBody.fromString('{"records":[{"id":1', 200),
      'queue': (_) => jsonBody(page([])),
      'calendar': (_) => jsonBody([]),
    });
    final adapters = <FaultInjectingAdapter>[];
    final (c, _) = await start({
      ServiceKind.sonarr: faulty(ServiceKind.sonarr, 's', server, const [
        ConnectionDropFault(afterBytes: 5),
      ], adapters),
    });
    final recent = slices<List<MediaItem>>(c.read(dashboardProvider).recent);
    expect(recent.single, isA<SliceFailed<List<MediaItem>>>());
  });

  test('a flaky server answers 503 once: the card shows the failure and a '
      'retry succeeds', () async {
    final adapters = <FaultInjectingAdapter>[];
    final (c, _) = await start({
      ServiceKind.sonarr: faulty(ServiceKind.sonarr, 's', healthyArr(), const [
        FlakyFault(failFirst: 1),
      ], adapters),
    });
    // The fault is per request URL: each card's first attempt failed.
    final first = slices<ActivitySummary>(c.read(dashboardProvider).activity);
    expect(first.single, isA<SliceFailed<ActivitySummary>>());
    expect(
      (first.single as SliceFailed<ActivitySummary>).error.category,
      ErrorCategory.serverError,
    );
    await c.read(dashboardProvider.notifier).retry(DashboardCard.activity);
    await pumpEventQueue(times: 100);
    final second = slices<ActivitySummary>(c.read(dashboardProvider).activity);
    expect(second.single, isA<SliceData<ActivitySummary>>());
    // upcoming and recent were not asked again
    expect(adapters.single.requestCount, 4);
  });
}
