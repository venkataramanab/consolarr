// SPDX-License-Identifier: GPL-3.0-or-later

// The dashboard on the app's own `activeConnectionProvider`, an in-memory
// server repository and fake HTTP servers: switching the active server in the
// middle of a load shows nothing of the old server and caches nothing for it.

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/data/arr_sources.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';

import '../servers/ui/support.dart' as ui;
import 'support.dart';

class _Factory implements SecureHttpClientFactory {
  _Factory(this.servers);

  final Map<String, FakeServer> servers;

  @override
  Dio create(ServerProfile profile) =>
      Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
        ..httpClientAdapter = servers[profile.id]!;
}

void main() {
  tearDown(disposeContainers);

  test('setActive in the middle of a load: no data and no cache row of the '
      'old server', () async {
    final a = FakeServer({
      'queue': (_) => jsonBody(page([queueJson(id: 1, title: 'Only On A')])),
      'calendar': (_) => jsonBody([
        episodeJson(
          id: 1,
          seriesId: 1,
          series: 'Only On A',
          airDateUtc: '2026-03-11T12:00:00Z',
        ),
      ]),
      'history': (_) => jsonBody(
        page([historyRowJson(id: 1, seriesId: 1, title: 'Only On A')]),
      ),
    });
    final b = FakeServer({
      'queue': (_) => jsonBody(page(const [])),
      'calendar': (_) => jsonBody([
        episodeJson(
          id: 2,
          seriesId: 2,
          series: 'Only On B',
          airDateUtc: '2026-03-12T12:00:00Z',
        ),
      ]),
      'history': (_) => jsonBody(page(const [])),
    });
    // A answers late: held until the user has switched to B.
    final release = Completer<void>();
    a.gate = release;

    final repo = ui.FakeServerRepository([
      ui.entry('a', name: 'Server A'),
      ui.entry('b', name: 'Server B', address: 'https://b.example'),
    ])..active[ServiceKind.sonarr] = 'a';

    final env = Env(now: () => fixedNow)
      ..serverIdsLoader = () async => {
        for (final e in repo.entries) e.profile.id,
      };
    final c = env.container(
      sources: {ServiceKind.sonarr: sonarrDashboardSource},
      realConnections: true,
      extra: [
        serverRepositoryProvider.overrideWithValue(repo),
        secureHttpClientFactoryProvider.overrideWithValue(
          _Factory({'a': a, 'b': b}),
        ),
      ],
    );
    c.listen(dashboardProvider, (_, _) {});
    await pumpEventQueue();
    expect(a.inFlight, greaterThan(0), reason: 'A is being asked');

    await repo.setActive(ServiceKind.sonarr, 'b');
    await pumpEventQueue();
    release.complete();
    await pumpEventQueue();
    await pumpEventQueue();

    String titles() => c.read(dashboardProvider).toString();
    final snapshot = c.read(dashboardProvider);
    for (final state in [snapshot.upcoming, snapshot.recent]) {
      final slices = switch (state) {
        CardData<List<MediaItem>>(:final slices) => slices,
        _ => const <CardSlice<List<MediaItem>>>[],
      };
      for (final s in slices) {
        expect(s.serverId, 'b');
        if (s is SliceData<List<MediaItem>>) {
          expect(s.value.map((i) => i.title), isNot(contains('Only On A')));
        }
      }
    }
    final upcoming = switch (snapshot.upcoming) {
      CardData<List<MediaItem>>(:final slices) => slices.single,
      _ => fail('upcoming of B expected: ${titles()}'),
    } as SliceData<List<MediaItem>>;
    expect(upcoming.serverId, 'b');
    expect(upcoming.value.single.title, 'Only On B');
    expect(
      env.cache.rows.keys.where((k) => k.$1 == 'a'),
      isEmpty,
      reason: 'no cache row for the server that was switched away from',
    );
    expect(env.cache.rows.keys.where((k) => k.$1 == 'b'), isNotEmpty);
  });
}
