// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'models_test.dart' show fullSeries;
import 'support/fake_adapter.dart';

Future<T> _inline<T>(T Function() work) async => work();

String _status(String version) =>
    jsonEncode({'version': version, 'appName': 'Sonarr', 'extra': 1});

SonarrClient _client(FakeAdapter a, {String base = 'https://sonarr.example'}) =>
    SonarrClient(
      dio: dioWith(a, base: base),
      parseRunner: _inline,
    );

void main() {
  group('systemStatus', () {
    test('returns the version and uses a relative api/v3 path', () async {
      final a = FakeAdapter.fixed(_status('4.0.9.2244'));
      final r = await _client(a).systemStatus();
      expect(r.valueOrNull?.version, '4.0.9.2244');
      expect(r.valueOrNull?.majorVersion, 4);
      expect(r.valueOrNull?.appName, 'Sonarr');
      expect(
        a.requests.single.uri.toString(),
        'https://sonarr.example/api/v3/system/status',
      );
    });

    test('keeps a reverse-proxy path prefix', () async {
      for (final base in [
        'https://sonarr.example/sonarr',
        'https://sonarr.example/sonarr/',
      ]) {
        final a = FakeAdapter.fixed(_status('3.0.10.1567'));
        await _client(a, base: base).systemStatus();
        expect(a.requests.single.uri.path, '/sonarr/api/v3/system/status');
      }
    });

    test('major version below 3 is unsupported_version', () async {
      final a = FakeAdapter.fixed(_status('2.0.0.5344'));
      final r = await _client(a).systemStatus();
      expect(r.errorOrNull?.category, ErrorCategory.unsupportedVersion);
    });

    test('legacy v2: 404 on v3 then legacy probe reports 2.x', () async {
      final a = FakeAdapter((o) {
        if (o.uri.path == '/api/system/status') {
          return FakeAdapter.reply(_status('2.0.0.5344'));
        }
        return FakeAdapter.reply('', status: 404);
      });
      final r = await _client(a).systemStatus();
      expect(r.errorOrNull?.category, ErrorCategory.unsupportedVersion);
      expect(a.requests.map((r) => r.uri.path), [
        '/api/v3/system/status',
        '/api/system/status',
      ]);
    });

    test('404 on both paths is not_found (wrong path prefix)', () async {
      final a = FakeAdapter.fixed('', status: 404);
      final r = await _client(a).systemStatus();
      expect(r.errorOrNull?.category, ErrorCategory.notFound);
    });

    test('a non-object or version-less body is parse_error', () async {
      for (final body in ['[]', '{"x":1}', '{"version":4}', 'nope']) {
        final r = await _client(FakeAdapter.fixed(body)).systemStatus();
        expect(r.errorOrNull?.category, ErrorCategory.parseError, reason: body);
      }
    });

    test('maps 401/403/5xx', () async {
      expect(
        (await _client(
          FakeAdapter.fixed('', status: 401),
        ).systemStatus()).errorOrNull?.category,
        ErrorCategory.authFailed,
      );
      expect(
        (await _client(
          FakeAdapter.fixed('', status: 403),
        ).systemStatus()).errorOrNull?.category,
        ErrorCategory.authFailed,
      );
      expect(
        (await _client(
          FakeAdapter.fixed('', status: 502),
        ).systemStatus()).errorOrNull?.category,
        ErrorCategory.serverError,
      );
    });
  });

  group('series', () {
    test('lists series from api/v3/series', () async {
      final a = FakeAdapter.fixed(
        jsonEncode([fullSeries(), fullSeries(id: 2)]),
      );
      final r = await _client(a).series();
      expect(r.valueOrNull?.map((s) => s.title), [
        'Example Show 1',
        'Example Show 2',
      ]);
      expect(a.requests.single.uri.path, '/api/v3/series');
    });

    test('a wrong-typed body is parse_error', () async {
      final r = await _client(FakeAdapter.fixed('{"a":1}')).series();
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
      final r2 = await _client(FakeAdapter.fixed('[{"id":"x","title":"y"}]'))
          .series();
      expect(r2.errorOrNull?.category, ErrorCategory.parseError);
    });

    test(
      'small bodies parse inline, large ones go through the runner',
      () async {
        var calls = 0;
        Future<T> counting<T>(T Function() work) async {
          calls++;
          return work();
        }

        final small = SonarrClient(
          dio: dioWith(FakeAdapter.fixed(jsonEncode([fullSeries()]))),
          parseRunner: counting,
        );
        await small.series();
        expect(calls, 0);

        final big = jsonEncode([
          for (var i = 0; i < 400; i++) fullSeries(id: i),
        ]);
        expect(big.length, greaterThan(SonarrClient.isolateThresholdBytes));
        final large = SonarrClient(
          dio: dioWith(FakeAdapter.fixed(big)),
          parseRunner: counting,
        );
        final r = await large.series();
        expect(calls, 1);
        expect(r.valueOrNull, hasLength(400));
      },
    );

    test('10,000 series parse in a real isolate', () async {
      final big = jsonEncode([
        for (var i = 0; i < 10000; i++)
          {
            'id': i,
            'title': 'Example Show $i',
            'statistics': {'episodeCount': i},
          },
      ]);
      final client = SonarrClient(dio: dioWith(FakeAdapter.fixed(big)));
      final r = await client.series();
      expect(r.valueOrNull, hasLength(10000));
      expect(r.valueOrNull!.last.statistics.episodeCount, 9999);
    });

    test('a parse failure inside the isolate is parse_error', () async {
      final bad = '[${List.filled(5000, '{"id":"x","title":"y"}').join(',')}]';
      final client = SonarrClient(dio: dioWith(FakeAdapter.fixed(bad)));
      final r = await client.series();
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
    });
  });

  group('network scenarios', () {
    test('connect timeout -> timeout', () async {
      final a = FakeAdapter(
        (o) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: o,
        ),
      );
      expect(
        (await _client(a).series()).errorOrNull?.category,
        ErrorCategory.timeout,
      );
    });

    test('connection dropped mid-body -> network_unreachable', () async {
      final a = FakeAdapter((_) => FakeAdapter.dropped('[{"id":1,'));
      expect(
        (await _client(a).series()).errorOrNull?.category,
        ErrorCategory.networkUnreachable,
      );
    });

    test('malformed JSON -> parse_error', () async {
      expect(
        (await _client(
          FakeAdapter.fixed('[{"id":1,'),
        ).series()).errorOrNull?.category,
        ErrorCategory.parseError,
      );
    });

    test('503 -> server_error', () async {
      expect(
        (await _client(
          FakeAdapter.fixed('', status: 503),
        ).series()).errorOrNull?.category,
        ErrorCategory.serverError,
      );
    });

    test('typed errors from the secure client pass through', () async {
      final a = FakeAdapter(
        (o) => throw DioException(
          requestOptions: o,
          error: const AppError(ErrorCategory.cleartextRefused),
        ),
      );
      expect(
        (await _client(a).series()).errorOrNull?.category,
        ErrorCategory.cleartextRefused,
      );
    });

    test('errors never carry the request URL or headers', () async {
      final a = FakeAdapter.fixed('', status: 500);
      final dio = dioWith(a, base: 'https://sonarr.example/secret-prefix')
        ..options.headers['X-Api-Key'] = 'test-key-0000';
      final r = await SonarrClient(dio: dio).series();
      final text = '${r.errorOrNull} ${r.errorOrNull?.debugDetail}';
      expect(text, isNot(contains('secret-prefix')));
      expect(text, isNot(contains('test-key')));
    });
  });

  group('artworkUri', () {
    final series = SonarrSeries.fromJson(fullSeries());

    test('resolves relative urls against the base, no key in the URL', () {
      final c = _client(FakeAdapter.fixed(''));
      final u = c.artworkUri(series, SonarrImageType.poster)!;
      expect(u.host, 'sonarr.example');
      expect(u.path, '/MediaCover/1/poster.jpg');
      expect(u.query, 'lastWrite=637000000000000000');
      expect(u.toString().toLowerCase(), isNot(contains('apikey')));
    });

    test('prepends the path prefix once', () {
      final c = _client(
        FakeAdapter.fixed(''),
        base: 'https://sonarr.example/tv',
      );
      expect(
        c.artworkUri(series, SonarrImageType.poster)!.path,
        '/tv/MediaCover/1/poster.jpg',
      );
      final already = SonarrSeries.fromJson({
        'id': 1,
        'title': 'x',
        'images': [
          {'coverType': 'poster', 'url': '/tv/MediaCover/1/poster.jpg'},
        ],
      });
      expect(
        c.artworkUri(already, SonarrImageType.poster)!.path,
        '/tv/MediaCover/1/poster.jpg',
      );
    });

    test('missing type gives null', () {
      final c = _client(FakeAdapter.fixed(''));
      expect(c.artworkUri(series, SonarrImageType.banner), isNull);
    });

    test('absolute / remote urls are never used', () {
      final s = SonarrSeries.fromJson({
        'id': 1,
        'title': 'x',
        'images': [
          {
            'coverType': 'poster',
            'url': 'https://images.example/p.jpg',
            'remoteUrl': 'https://images.example/p.jpg',
          },
          {'coverType': 'banner', 'remoteUrl': 'https://images.example/b.jpg'},
        ],
      });
      final c = _client(FakeAdapter.fixed(''));
      expect(c.artworkUri(s, SonarrImageType.poster), isNull);
      expect(c.artworkUri(s, SonarrImageType.banner), isNull);
    });

    test('an api key smuggled into the url query is dropped', () {
      final s = SonarrSeries.fromJson({
        'id': 1,
        'title': 'x',
        'images': [
          {
            'coverType': 'poster',
            'url': '/MediaCover/1/poster.jpg?lastWrite=1&apikey=test-key-0000',
          },
        ],
      });
      final u = _client(FakeAdapter.fixed(''))
          .artworkUri(s, SonarrImageType.poster)!;
      expect(u.toString(), isNot(contains('test-key')));
      expect(u.query, 'lastWrite=1');
    });
  });
}
