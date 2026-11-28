// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart' show isolateParseRunner;
import 'package:consolarr/shared/time/calendar_days.dart';
import 'package:consolarr/features/dashboard/application/dashboard_cancel.dart';
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/application/dashboard_sources.dart';
import 'package:consolarr/features/dashboard/data/arr_sources.dart';
import 'package:consolarr/features/dashboard/data/torrent_source.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart'
    show DelugeHost, DelugeHostRequired, Torrent, TorrentState, TransferInfo;

import '../torrents/support.dart' show FakeTorrentClient;
import 'support.dart';

SourceContext ctx(
  ServiceKind kind,
  FakeServer server, {
  Duration offset = Duration.zero,
  DateTime? now,
  SourceSession? session,
  bool realIsolate = false,
}) {
  final conn = connection(kind, 'x', server);
  return SourceContext(
    connection: conn,
    dio: cancellableDio(conn.dio),
    loadCredentials: () async => const ServerCredentials(),
    session: session ?? SourceSession(),
    now: now ?? fixedNow,
    utcOffset: offset,
    onRowsSkipped: (_) {},
    runner: realIsolate ? isolateParseRunner : <T>(f) async => f(),
  );
}

void main() {
  group('calendar days', () {
    test('an instant takes the viewer zone, a date-only value never does', () {
      final instant = DateTime.utc(2026, 3, 10, 23, 30);
      expect(
        calendarDay(instant, const Duration(hours: 14)),
        DateTime.utc(2026, 3, 11),
      );
      expect(
        calendarDay(instant, const Duration(hours: -12)),
        DateTime.utc(2026, 3, 10),
      );
      final dateOnly = DateTime.utc(2026, 3, 12);
      expect(dateOnlyDay(dateOnly), DateTime.utc(2026, 3, 12));
    });

    test('parseDayText reads plain dates only', () {
      expect(parseDayText('2026-03-10'), DateTime.utc(2026, 3, 10));
      expect(parseDayText('2026-13-10'), isNull);
      expect(parseDayText('soon'), isNull);
      expect(parseDayText(null), isNull);
    });
  });

  group('Sonarr', () {
    late FakeServer server;
    setUp(() => server = FakeServer());

    test(
      'upcoming: window, order, local days, poster without credentials',
      () async {
        server.routes['calendar'] = (_) => jsonBody([
          episodeJson(id: 3, seriesId: 3, airDateUtc: '2026-03-20T20:00:00Z'),
          episodeJson(id: 1, seriesId: 1, airDateUtc: '2026-03-10T23:30:00Z'),
          episodeJson(id: 2, seriesId: 2, airDateUtc: '2026-03-12T01:00:00Z'),
          // before today (local) and beyond the window
          episodeJson(id: 4, seriesId: 4, airDateUtc: '2026-03-09T12:00:00Z'),
          episodeJson(id: 5, seriesId: 5, airDateUtc: '2026-04-30T12:00:00Z'),
          episodeJson(id: 6, seriesId: 6, airDate: '2026-03-11'),
        ]);
        final r = await sonarrDashboardSource.upcoming!(
          ctx(ServiceKind.sonarr, server, offset: const Duration(hours: 14)),
        );
        final items = r.valueOrNull!;
        // At UTC+14 "now" is the 11th, so the episode at 23:30Z on the 10th
        // (the 11th local) is today and the one on the 9th is gone.
        expect(items.map((i) => i.id), ['ep:1', 'ep:6', 'ep:2', 'ep:3']);
        expect(items.first.day, DateTime.utc(2026, 3, 11));
        expect(items.first.link.location, '/sonarr/series/1');
        expect(items.first.link.target, DashboardTarget.detail);
        final art = items.first.artwork!;
        expect(art.host, 'x.example');
        expect(art.path, '/MediaCover/1/poster.jpg');
        expect(art.toString().toLowerCase(), isNot(contains('apikey')));
        final request = server.requests.single;
        expect(request.method, 'GET');
        // one day of slack on each side; the local day is decided on the client
        expect(request.uri.queryParameters['start'], '2026-03-10');
        expect(request.uri.queryParameters['end'], '2026-03-26');
      },
    );

    test('the same air time lands on the 10th at UTC-12', () async {
      server.routes['calendar'] = (_) => jsonBody([
        episodeJson(id: 1, seriesId: 1, airDateUtc: '2026-03-10T23:30:00Z'),
      ]);
      final r = await sonarrDashboardSource.upcoming!(
        ctx(ServiceKind.sonarr, server, offset: const Duration(hours: -12)),
      );
      expect(r.valueOrNull!.single.day, DateTime.utc(2026, 3, 10));
    });

    test(
      'episodes without a series title are skipped, the list is capped',
      () async {
        server.routes['calendar'] = (_) => jsonBody([
          for (var i = 1; i <= 40; i++)
            episodeJson(
              id: i,
              seriesId: i,
              airDateUtc:
                  '2026-03-11T${(i % 24).toString().padLeft(2, '0')}:00:00Z',
            ),
          {
            'id': 99,
            'seriesId': 99,
            'seasonNumber': 1,
            'episodeNumber': 1,
            'airDateUtc': '2026-03-11T01:00:00Z',
          },
        ]);
        final r = await sonarrDashboardSource.upcoming!(
          ctx(ServiceKind.sonarr, server),
        );
        expect(r.valueOrNull!, hasLength(kCarouselItems));
        expect(r.valueOrNull!.map((i) => i.id), isNot(contains('ep:99')));
      },
    );

    test('recent: one poster per series, newest first, deep link', () async {
      server.routes['history'] = (_) => jsonBody(
        page([
          historyRowJson(id: 1, seriesId: 7, date: '2026-03-10T08:00:00Z'),
          historyRowJson(id: 2, seriesId: 7, date: '2026-03-10T09:00:00Z'),
          historyRowJson(
            id: 3,
            seriesId: 8,
            title: 'Other Show',
            date: '2026-03-09T09:00:00Z',
          ),
        ]),
      );
      final r = await sonarrDashboardSource.recent!(
        ctx(ServiceKind.sonarr, server),
      );
      final items = r.valueOrNull!;
      expect(items.map((i) => i.id), ['hist:2', 'hist:3']);
      expect(items.first.link.location, '/sonarr/series/7');
      expect(items.first.season, 1);
      expect(items.first.at, DateTime.utc(2026, 3, 10, 9));
      expect(server.requests.single.method, 'GET');
    });

    test(
      'activity: counts the whole queue, keeps three rows, attention first',
      () async {
        server.routes['queue'] = (_) => jsonBody(
          page([
            for (var i = 1; i <= 12; i++)
              queueJson(id: i, left: 1000 - i * 50, series: 'Show $i'),
            queueJson(
              id: 100,
              status: 'completed',
              tdStatus: 'warning',
              tdState: 'importFailed',
              series: 'Stuck Show',
            ),
            queueJson(id: 101, status: 'paused'),
          ]),
        );
        final r = await sonarrDashboardSource.activity!(
          ctx(ServiceKind.sonarr, server),
        );
        final s = r.valueOrNull!;
        expect(s.active, 12);
        expect(s.attention, 1);
        expect(s.rows, hasLength(kActivityRows));
        expect(s.rows.first.title, 'Stuck Show');
        expect(s.rows.first.state, ActivityState.attention);
        expect(s.rows[1].progress, greaterThanOrEqualTo(s.rows[2].progress));
        expect(s.link.location, '/sonarr');
        expect(s.link.target, DashboardTarget.tab);
      },
    );

    test('errors keep their category', () async {
      server.routes['calendar'] = (_) => jsonBody({}, status: 401);
      final r = await sonarrDashboardSource.upcoming!(
        ctx(ServiceKind.sonarr, server),
      );
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
    });
  });

  group('Radarr', () {
    late FakeServer server;
    setUp(() => server = FakeServer());

    for (final (label, offset, today, expectedText) in [
      ('UTC+14', const Duration(hours: 14), 11, 1),
      ('UTC-12', const Duration(hours: -12), 10, 2),
    ]) {
      test('release dates are date-only: $label never moves them', () async {
        server.routes['calendar'] = (_) => jsonBody([
          movieJson(id: 5, digitalRelease: '2026-03-12T00:00:00Z'),
        ]);
        final r = await radarrDashboardSource.upcoming!(
          ctx(ServiceKind.radarr, server, offset: offset),
        );
        final item = r.valueOrNull!.single;
        expect(item.day, DateTime.utc(2026, 3, 12));
        expect(item.release, MovieRelease.digital);
        expect(item.link.location, '/radarr/movie/5');
        expect(
          daysBetween(DateTime.utc(2026, 3, today), item.day!),
          expectedText,
        );
      });
    }

    test('picks the soonest release inside the window', () async {
      server.routes['calendar'] = (_) => jsonBody([
        movieJson(
          id: 1,
          inCinemas: '2026-02-01T00:00:00Z',
          digitalRelease: '2026-03-15T00:00:00Z',
          physicalRelease: '2026-03-13T00:00:00Z',
        ),
        movieJson(id: 2, inCinemas: '2026-01-01T00:00:00Z'),
      ]);
      final r = await radarrDashboardSource.upcoming!(
        ctx(ServiceKind.radarr, server),
      );
      final items = r.valueOrNull!;
      expect(items.single.release, MovieRelease.disc);
      expect(items.single.day, DateTime.utc(2026, 3, 13));
    });

    test('recent: movie link, no episode numbers', () async {
      server.routes['history'] = (_) => jsonBody(
        page([historyRowJson(id: 1, movieId: 41, title: 'Example Movie')]),
      );
      final r = await radarrDashboardSource.recent!(
        ctx(ServiceKind.radarr, server),
      );
      final item = r.valueOrNull!.single;
      expect(item.link.location, '/radarr/movie/41');
      expect(item.link.destination, DashboardDestination.movie);
      expect(item.season, isNull);
    });
  });

  group('large bodies (real isolate, unsendable adapter)', () {
    // A closure that captured the client would make Isolate.run throw and the
    // card would show "offline" for every list over 64 KB.
    String big(List<Map<String, Object?>> rows) {
      final body = jsonEncode(rows);
      expect(body.length, greaterThan(64 * 1024));
      return body;
    }

    String bigPage(List<Map<String, Object?>> rows) {
      final body = jsonEncode(page(rows, pageSize: 5000));
      expect(body.length, greaterThan(64 * 1024));
      return body;
    }

    String pad(int i) => '${'x' * 80}$i';

    test('Sonarr calendar, queue and history', () async {
      final server = FakeServer({
        'calendar': (_) => ResponseBody.fromString(
          big([
            for (var i = 1; i <= 500; i++)
              {
                ...episodeJson(
                  id: i,
                  seriesId: i,
                  series: 'Show ${pad(i)}',
                  airDateUtc: '2026-03-11T10:00:00Z',
                ),
                'overview': pad(i),
              },
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
        'queue': (_) => ResponseBody.fromString(
          bigPage([
            for (var i = 1; i <= 600; i++)
              queueJson(id: i, title: 'Release.${pad(i)}'),
          ]),
          200,
        ),
        'history': (_) => ResponseBody.fromString(
          bigPage([
            for (var i = 1; i <= 600; i++)
              {...historyRowJson(id: i, seriesId: i), 'sourceTitle': pad(i)},
          ]),
          200,
        ),
      });
      final c = ctx(ServiceKind.sonarr, server, realIsolate: true);
      final up = await sonarrDashboardSource.upcoming!(c);
      expect(up.errorOrNull, isNull);
      expect(up.valueOrNull, hasLength(kCarouselItems));
      final act = await sonarrDashboardSource.activity!(c);
      expect(act.errorOrNull, isNull);
      expect(act.valueOrNull!.active, 600);
      final rec = await sonarrDashboardSource.recent!(c);
      expect(rec.errorOrNull, isNull);
      expect(rec.valueOrNull, hasLength(kCarouselItems));
    });

    test('Radarr calendar, queue and history', () async {
      final server = FakeServer({
        'calendar': (_) => ResponseBody.fromString(
          big([
            for (var i = 1; i <= 500; i++)
              {
                ...movieJson(
                  id: i,
                  title: 'Movie ${pad(i)}',
                  digitalRelease: '2026-03-12T00:00:00Z',
                ),
                'overview': pad(i),
              },
          ]),
          200,
        ),
        'queue': (_) => ResponseBody.fromString(
          bigPage([
            for (var i = 1; i <= 600; i++)
              queueJson(id: i, movieId: i, title: 'Release.${pad(i)}'),
          ]),
          200,
        ),
        'history': (_) => ResponseBody.fromString(
          bigPage([
            for (var i = 1; i <= 600; i++)
              {...historyRowJson(id: i, movieId: i), 'sourceTitle': pad(i)},
          ]),
          200,
        ),
      });
      final c = ctx(ServiceKind.radarr, server, realIsolate: true);
      expect((await radarrDashboardSource.upcoming!(c)).errorOrNull, isNull);
      expect((await radarrDashboardSource.activity!(c)).errorOrNull, isNull);
      expect((await radarrDashboardSource.recent!(c)).errorOrNull, isNull);
    });
  });

  group('read-only', () {
    test('every request of every card of both arr sources is a GET', () async {
      final server = FakeServer({
        'calendar': (_) => jsonBody([]),
        'queue': (_) => jsonBody(page([])),
        'history': (_) => jsonBody(page([])),
      });
      for (final source in [sonarrDashboardSource, radarrDashboardSource]) {
        final c = ctx(ServiceKind.sonarr, server);
        await source.activity!(c);
        await source.upcoming!(c);
        await source.recent!(c);
      }
      expect(server.requests, isNotEmpty);
      expect(server.requests.map((r) => r.method).toSet(), {'GET'});
      expect(
        server.requests.map((r) => r.uri.toString().toLowerCase()),
        everyElement(isNot(contains('apikey'))),
      );
    });
  });

  group('torrent clients', () {
    final saved = Map.of(torrentClientFactories);
    tearDown(() {
      torrentClientFactories
        ..clear()
        ..addAll(saved);
    });

    Torrent torrent(
      String hash,
      TorrentState state, {
      double progress = 0.5,
      int speed = 100,
    }) => Torrent(
      hash: hash,
      name: 'Example $hash',
      state: state,
      progress: progress,
      size: 1000,
      dlSpeed: speed,
      upSpeed: 0,
      ratio: 0,
    );

    test(
      'summary: counts, speeds, the top rows without sorting everything',
      () {
        final list = [
          for (var i = 0; i < 10000; i++)
            torrent(
              't$i',
              i % 3 == 0 ? TorrentState.downloading : TorrentState.seeding,
              progress: (i % 100) / 100,
            ),
          torrent('bad', TorrentState.error, progress: 0.1),
        ];
        final stopwatch = Stopwatch()..start();
        final s = summarizeTorrents(
          list,
          const TransferInfo(
            dlSpeed: 2048,
            upSpeed: 512,
            dlTotal: 0,
            upTotal: 0,
          ),
        );
        stopwatch.stop();
        expect(s.active, 3334);
        expect(s.attention, 1);
        expect(s.rows, hasLength(kActivityRows));
        expect(s.rows.first.id, 'bad');
        expect(s.rows.first.state, ActivityState.attention);
        expect(s.rows[1].progress, greaterThanOrEqualTo(s.rows[2].progress));
        expect(s.rows[1].progress, 0.99);
        expect(s.downSpeed, 2048);
        expect(s.upSpeed, 512);
        expect(s.speedUnavailable, isFalse);
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      },
    );

    test('missing statistics are marked, not an error', () {
      final s = summarizeTorrents([
        torrent('a', TorrentState.downloading),
      ], null);
      expect(s.speedUnavailable, isTrue);
      expect(s.downSpeed, isNull);
      expect(s.active, 1);
    });

    test('seeding only is idle', () {
      final s = summarizeTorrents([torrent('a', TorrentState.seeding)], null);
      expect(s.isIdle, isTrue);
    });

    test('the client comes from the registry; the session is reused and '
        'forgotten with the connection', () async {
      final fake = FakeTorrentClient(
        torrents: [torrent('a', TorrentState.downloading)],
      );
      var created = 0;
      torrentClientFactories[ServiceKind.qbittorrent] = (_) {
        created++;
        return fake;
      };
      final session = SourceSession();
      final source = torrentDashboardSource(ServiceKind.qbittorrent);
      final server = FakeServer();
      final c = ctx(ServiceKind.qbittorrent, server, session: session);
      await source.activity!(c);
      await source.activity!(c);
      expect(created, 1);
      expect(fake.listCalls, 2);
      expect(fake.calls, isNot(contains('forgetSession')));
      session.close();
      expect(created, 1);
    });

    test('a Deluge that needs its host is a marked slice error without the '
        'host list', () async {
      final fake = FakeTorrentClient(kind: ServiceKind.deluge)
        ..failWith(
          const DelugeHostRequired([
            DelugeHost(id: 'h1', host: '192.0.2.10', port: 58846),
          ]),
        );
      torrentClientFactories[ServiceKind.deluge] = (_) => fake;
      final r = await torrentDashboardSource(ServiceKind.deluge)
          .activity!(ctx(ServiceKind.deluge, FakeServer()));
      final error = r.errorOrNull!;
      expect(error, isNot(isA<DelugeHostRequired>()));
      expect(error, isA<HostChoiceRequired>());
      expect(error.toString(), isNot(contains('192.0.2')));
    });

    test('the registry maps the three torrent kinds and nothing else', () {
      expect(
        dashboardSources.keys.toSet(),
        ServiceKind.values.toSet(),
        reason: 'one line per kind',
      );
      for (final kind in [
        ServiceKind.qbittorrent,
        ServiceKind.transmission,
        ServiceKind.deluge,
      ]) {
        expect(dashboardSources[kind]!.feeds(DashboardCard.activity), isTrue);
        expect(dashboardSources[kind]!.feeds(DashboardCard.upcoming), isFalse);
        expect(dashboardSources[kind]!.feeds(DashboardCard.recent), isFalse);
      }
      for (final kind in [ServiceKind.sonarr, ServiceKind.radarr]) {
        for (final card in DashboardCard.values) {
          expect(dashboardSources[kind]!.feeds(card), isTrue);
        }
      }
    });
  });
}
