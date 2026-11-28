// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:isolate';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import '../support/fake_adapter.dart';

/// Cannot be sent to another isolate, like the real `HttpClient` adapter.
class _UnsendableAdapter extends FakeAdapter {
  _UnsendableAdapter(String body) : super((_) => FakeAdapter.reply(body));

  final ReceivePort port = ReceivePort();

  @override
  void close({bool force = false}) => port.close();
}

Map<String, Object?> _sonarrRow({
  int id = 1,
  Object? eventType = 'downloadFolderImported',
  String date = '2026-03-01T10:00:00Z',
  bool withSeries = true,
}) => {
  'id': id,
  'episodeId': 100 + id,
  'seriesId': 7,
  'sourceTitle': 'Example.Show.S02E05.1080p',
  'eventType': ?eventType,
  'date': date,
  if (withSeries)
    'series': {
      'id': 7,
      'title': 'Example Show',
      'images': [
        {'coverType': 'poster', 'url': '/MediaCover/7/poster.jpg?lastWrite=1'},
      ],
    },
  'episode': {'seasonNumber': 2, 'episodeNumber': 5, 'title': 'Pilot'},
};

Map<String, Object?> _radarrRow({int id = 1, Object? eventType = 3}) => {
  'id': id,
  'movieId': 40 + id,
  'sourceTitle': 'Example.Movie.2025.1080p',
  'eventType': ?eventType,
  'date': '2026-03-02T11:30:00Z',
  'movie': {
    'id': 40 + id,
    'title': 'Example Movie',
    'images': [
      {'coverType': 'poster', 'url': '/MediaCover/41/poster.jpg'},
    ],
  },
};

String _page(List<Object?> records) => jsonEncode({
  'page': 1,
  'pageSize': 20,
  'totalRecords': records.length,
  'records': records,
});

SonarrClient _sonarr(FakeAdapter a, {ParseRunner? runner}) =>
    SonarrClient(dio: dioWith(a), parseRunner: runner ?? (<T>(f) async => f()));

RadarrClient _radarr(FakeAdapter a, {ParseRunner? runner}) => RadarrClient(
  dio: dioWith(a, base: 'https://radarr.example'),
  parseRunner: runner ?? (<T>(f) async => f()),
);

void main() {
  group('request', () {
    test(
      'Sonarr asks for the newest imports with series and episode',
      () async {
        final adapter = FakeAdapter.fixed(_page([_sonarrRow()]));
        await _sonarr(adapter).recentImports(limit: 15);
        final q = adapter.requests.single.uri.queryParameters;
        expect(adapter.requests.single.uri.path, '/api/v3/history');
        expect(q['pageSize'], '15');
        expect(q['sortKey'], 'date');
        expect(q['sortDirection'], 'descending');
        expect(q['eventType'], '3');
        expect(q['includeSeries'], 'true');
        expect(q['includeEpisode'], 'true');
        expect(q.containsKey('includeMovie'), isFalse);
        expect(adapter.requests.single.method, 'GET');
      },
    );

    test('Radarr asks for the movie, not series or episode', () async {
      final adapter = FakeAdapter.fixed(_page([_radarrRow()]));
      await _radarr(adapter).recentImports();
      final q = adapter.requests.single.uri.queryParameters;
      expect(q['includeMovie'], 'true');
      expect(q.containsKey('includeSeries'), isFalse);
      expect(q['pageSize'], '20');
    });

    test('the limit is clamped to a sane page size', () async {
      final adapter = FakeAdapter.fixed(_page([_sonarrRow()]));
      await _sonarr(adapter).recentImports(limit: 100000);
      expect(adapter.requests.last.uri.queryParameters['pageSize'], '100');
      await _sonarr(adapter).recentImports(limit: 0);
      expect(adapter.requests.last.uri.queryParameters['pageSize'], '1');
    });

    test('keeps a path prefix and never puts a key in the URL', () async {
      final adapter = FakeAdapter.fixed(_page([_sonarrRow()]));
      final client = SonarrClient(
        dio: dioWith(adapter, base: 'https://nas.example/sonarr'),
        parseRunner: <T>(f) async => f(),
      );
      await client.recentImports();
      expect(adapter.requests.single.uri.path, '/sonarr/api/v3/history');
      expect(
        adapter.requests.single.uri.toString().toLowerCase(),
        isNot(contains('apikey')),
      );
    });
  });

  group('parsing', () {
    test('Sonarr v3 string event type, embedded series and episode', () async {
      final r = await _sonarr(FakeAdapter.fixed(_page([_sonarrRow()])))
          .recentImports();
      final item = r.valueOrNull!.single;
      expect(item.id, 1);
      expect(item.seriesId, 7);
      expect(item.episodeId, 101);
      expect(item.movieId, isNull);
      expect(item.seasonNumber, 2);
      expect(item.episodeNumber, 5);
      expect(item.title, 'Example Show');
      expect(item.episodeTitle, 'Pilot');
      expect(item.date, DateTime.utc(2026, 3, 1, 10));
      expect(item.date!.isUtc, isTrue);
      expect(item.images.single.type, ArrImageType.poster);
    });

    test('Radarr v4 numeric event type and embedded movie', () async {
      final r = await _radarr(FakeAdapter.fixed(_page([_radarrRow()])))
          .recentImports();
      final item = r.valueOrNull!.single;
      expect(item.movieId, 41);
      expect(item.title, 'Example Movie');
      expect(item.seriesId, isNull);
      expect(item.images, isNotEmpty);
    });

    test('a bare array body (older servers) parses too', () async {
      final r = await _sonarr(
        FakeAdapter.fixed(jsonEncode([_sonarrRow(), _sonarrRow(id: 2)])),
      ).recentImports();
      expect(r.valueOrNull!.map((e) => e.id), [1, 2]);
    });

    test(
      'rows of other event types are dropped, a missing type is kept',
      () async {
        final r = await _sonarr(
          FakeAdapter.fixed(
            _page([
              _sonarrRow(eventType: 'grabbed'),
              _sonarrRow(id: 2, eventType: 1),
              _sonarrRow(id: 3, eventType: 'DownloadFolderImported'),
              _sonarrRow(id: 4, eventType: null),
              _sonarrRow(id: 5, eventType: 3),
            ]),
          ),
        ).recentImports();
        expect(r.valueOrNull!.map((e) => e.id), [3, 4, 5]);
      },
    );

    test('absent embedded objects still give an item with ids', () async {
      final r = await _sonarr(
        FakeAdapter.fixed(_page([_sonarrRow(withSeries: false)])),
      ).recentImports();
      final item = r.valueOrNull!.single;
      expect(item.title, isNull);
      expect(item.images, isEmpty);
      expect(item.seriesId, 7);
    });

    test('a malformed row is skipped and counted, the rest parse', () async {
      final r = await _sonarr(
        FakeAdapter.fixed(
          _page([
            _sonarrRow(),
            'junk',
            {'no': 'id'},
          ]),
        ),
      ).recentImports();
      expect(r.valueOrNull!.length, 1);
    });

    test('no row parses -> parse_error', () async {
      final r = await _sonarr(FakeAdapter.fixed(_page(['junk', 5])))
          .recentImports();
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
    });

    test('not JSON and wrong shapes -> parse_error', () async {
      for (final body in ['<html>', '"text"', '{"records": 5}', '']) {
        final r = await _sonarr(FakeAdapter.fixed(body)).recentImports();
        expect(r.errorOrNull?.category, ErrorCategory.parseError, reason: body);
      }
    });

    test('an empty page is an empty list, not an error', () async {
      final r = await _sonarr(FakeAdapter.fixed(_page([]))).recentImports();
      expect(r.valueOrNull, isEmpty);
    });

    test('a bad date is kept as null, not a failure', () async {
      final r = await _sonarr(
        FakeAdapter.fixed(_page([_sonarrRow(date: 'soon')])),
      ).recentImports();
      expect(r.valueOrNull!.single.date, isNull);
    });

    test('server errors map to categories', () async {
      expect(
        (await _sonarr(
          FakeAdapter.fixed('{}', status: 401),
        ).recentImports()).errorOrNull?.category,
        ErrorCategory.authFailed,
      );
      expect(
        (await _radarr(
          FakeAdapter.fixed('{}', status: 503),
        ).recentImports()).errorOrNull?.category,
        ErrorCategory.serverError,
      );
    });

    test(
      'a connection dropped mid-body fails, it never returns half a list',
      () async {
        final r = await _sonarr(
          FakeAdapter((_) => FakeAdapter.dropped('{"records":[{"id":1')),
        ).recentImports();
        expect(r.errorOrNull, isNotNull);
      },
    );
  });

  group('isolate', () {
    // An unsendable adapter plus the real runner and a body over 64 KB: a
    // closure capturing the client would make Isolate.run throw.
    test('a body over 64 KB parses off the UI isolate (Sonarr)', () async {
      final rows = [
        for (var i = 1; i <= 600; i++)
          {..._sonarrRow(id: i), 'sourceTitle': 'Example.Show.${'x' * 120}.$i'},
      ];
      final body = _page(rows);
      expect(body.length, greaterThan(ArrClientBase.isolateThresholdBytes));
      final r = await _sonarr(
        _UnsendableAdapter(body),
        runner: isolateParseRunner,
      ).recentImports(limit: 100);
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull!.length, 600);
    });

    test('a body over 64 KB parses off the UI isolate (Radarr)', () async {
      final rows = [
        for (var i = 1; i <= 600; i++)
          {..._radarrRow(id: i), 'sourceTitle': 'Example.${'x' * 120}.$i'},
      ];
      final body = _page(rows);
      expect(body.length, greaterThan(ArrClientBase.isolateThresholdBytes));
      final r = await _radarr(
        _UnsendableAdapter(body),
        runner: isolateParseRunner,
      ).recentImports(limit: 100);
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull!.length, 600);
    });
  });
}
