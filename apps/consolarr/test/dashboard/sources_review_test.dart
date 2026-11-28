// SPDX-License-Identifier: GPL-3.0-or-later

// Review fixes of PR #10 for the data layer: recent imports of a season pack,
// the Sonarr window in far-away zones and the torrent client's lifetime.

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_cancel.dart';
import 'package:consolarr/shared/time/calendar_days.dart';
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/data/arr_sources.dart';
import 'package:consolarr/features/dashboard/data/torrent_source.dart';
import 'package:consolarr/features/servers/domain/server_models.dart'
    show ServerCredentials;
import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

SourceContext _ctx(
  ServiceKind kind,
  FakeServer server, {
  Duration offset = Duration.zero,
  SourceSession? session,
}) {
  final conn = connection(kind, 'x', server);
  return SourceContext(
    connection: conn,
    dio: cancellableDio(conn.dio),
    loadCredentials: () async => const ServerCredentials(),
    session: session ?? SourceSession(),
    now: fixedNow,
    utcOffset: offset,
    onRowsSkipped: (_) {},
    runner: <T>(f) async => f(),
  );
}

/// A torrent client whose two reads can be held back.
class _GatedClient implements TorrentClient {
  final listStarted = Completer<void>();
  final transferStarted = Completer<void>();
  final release = Completer<void>();
  int forgotten = 0;

  @override
  Future<Result<List<Torrent>>> listTorrents() async {
    listStarted.complete();
    await release.future;
    return const Result.ok([]);
  }

  @override
  Future<Result<TransferInfo>> transferInfo() async {
    transferStarted.complete();
    await release.future;
    return const Result.ok(
      TransferInfo(dlSpeed: 1, upSpeed: 2, dlTotal: 0, upTotal: 0),
    );
  }

  @override
  void forgetSession() => forgotten++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  group('recent imports', () {
    test('a season pack still leaves a full carousel', () async {
      server.routes['history'] = (_) => jsonBody(
        page([
          // 30 episodes of one series in one import, then five other series
          for (var i = 1; i <= 30; i++)
            historyRowJson(id: i, seriesId: 1, date: '2026-03-10T10:00:00Z'),
          for (var s = 2; s <= 6; s++)
            historyRowJson(
              id: 100 + s,
              seriesId: s,
              title: 'Show $s',
              date: '2026-03-09T10:00:00Z',
            ),
        ]),
      );
      final r = await sonarrDashboardSource.recent!(
        _ctx(ServiceKind.sonarr, server),
      );
      expect(r.valueOrNull!.length, 6);
      expect(
        server.requests.single.uri.queryParameters['pageSize'],
        '100',
        reason: 'one page of the most the server allows',
      );
    });

    test(
      'after one entry per movie the list is cut to the carousel size',
      () async {
        server.routes['history'] = (_) => jsonBody(
          page([
            for (var i = 1; i <= 100; i++)
              historyRowJson(id: i, movieId: i, title: 'Movie $i'),
          ]),
        );
        final r = await radarrDashboardSource.recent!(
          _ctx(ServiceKind.radarr, server),
        );
        expect(r.valueOrNull!.length, kCarouselItems);
      },
    );
  });

  group('Sonarr calendar window in any zone', () {
    for (final hours in [10, 14, -12]) {
      test(
        'UTC${hours > 0 ? '+' : ''}$hours: the request covers every UTC '
        'date of the 15 local days; the client keeps the local days',
        () async {
          final offset = Duration(hours: hours);
          final today = calendarDay(fixedNow, offset);
          server.routes['calendar'] = (_) => jsonBody([
            // first instant of the first local day, last instant of the last
            episodeJson(
              id: 1,
              seriesId: 1,
              airDateUtc: today.subtract(offset).toIso8601String(),
            ),
            episodeJson(
              id: 2,
              seriesId: 2,
              airDateUtc: today
                  .add(const Duration(days: 15))
                  .subtract(offset)
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            ),
            // just before the first and just after the last local day
            episodeJson(
              id: 3,
              seriesId: 3,
              airDateUtc: today
                  .subtract(offset)
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            ),
            episodeJson(
              id: 4,
              seriesId: 4,
              airDateUtc: today
                  .add(const Duration(days: 15))
                  .subtract(offset)
                  .toIso8601String(),
            ),
          ]);
          final r = await sonarrDashboardSource.upcoming!(
            _ctx(ServiceKind.sonarr, server, offset: offset),
          );
          expect(r.valueOrNull!.map((i) => i.id), ['ep:1', 'ep:2']);
          final q = server.requests.single.uri.queryParameters;
          final start = DateTime.parse(q['start']!);
          final end = DateTime.parse(q['end']!);
          final firstInstant = today.subtract(offset);
          final lastInstant = today
              .add(const Duration(days: 15))
              .subtract(offset)
              .subtract(const Duration(seconds: 1));
          expect(
            !start.isAfter(
              DateTime.utc(
                firstInstant.year,
                firstInstant.month,
                firstInstant.day,
              ),
            ),
            isTrue,
            reason: 'start ${q['start']} covers the first UTC date',
          );
          expect(
            !end.isBefore(
              DateTime.utc(
                lastInstant.year,
                lastInstant.month,
                lastInstant.day,
              ),
            ),
            isTrue,
            reason: 'end ${q['end']} covers the last UTC date',
          );
        },
      );
    }
  });

  group('torrent client lifetime', () {
    test('the list and the statistics are asked together', () async {
      final client = _GatedClient();
      torrentClientFactories[ServiceKind.qbittorrent] = (_) => client;
      final run = torrentDashboardSource(ServiceKind.qbittorrent)
          .activity!(_ctx(ServiceKind.qbittorrent, server));
      await client.listStarted.future;
      // The statistics did not wait for the list.
      await client.transferStarted.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('transferInfo waited for listTorrents'),
      );
      client.release.complete();
      final summary = (await run).valueOrNull!;
      expect(summary.downSpeed, 1);
    });

    test(
      'a client created after the session closed is forgotten at once',
      () async {
        final client = _GatedClient();
        torrentClientFactories[ServiceKind.qbittorrent] = (_) => client;
        final session = SourceSession();
        final run = torrentDashboardSource(ServiceKind.qbittorrent)
            .activity!(_ctx(ServiceKind.qbittorrent, server, session: session));
        // The connection changed while the credentials were being read.
        session.close();
        client.release.complete();
        await run;
        expect(client.forgotten, 1);
        expect(session.has('torrent'), isFalse);
      },
    );

    test(
      'a session that is still open keeps its client until it closes',
      () async {
        final client = _GatedClient()..release.complete();
        torrentClientFactories[ServiceKind.qbittorrent] = (_) => client;
        final session = SourceSession();
        await torrentDashboardSource(ServiceKind.qbittorrent)
            .activity!(_ctx(ServiceKind.qbittorrent, server, session: session));
        expect(client.forgotten, 0);
        session.close();
        expect(client.forgotten, 1);
      },
    );
  });
}
