// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/logging/logging_interceptor.dart';
import 'package:consolarr/shared/logging/route_shape.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

// Canaries: none of these may ever reach a log line.
const _host = 'canary-host.invalid';
const _key = 'test-key-CANARY0000';
const _user = 'canaryuser';
const _pass = 'canarypass';
const _title = 'Canary Movie Title';

class _Lines {
  final List<(LogLevel, String)> lines = [];
  AppLogger logger({LogLevel min = LogLevel.debug}) =>
      AppLogger(sink: (l, m) => lines.add((l, m)), minLevel: min);
  String get all => lines.map((l) => l.$2).join('\n');
}

Dio _dio(
  _Lines out,
  HttpClientAdapter adapter, {
  String prefix = '',
  LogLevel min = LogLevel.debug,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://$_host:7878$prefix',
      headers: {
        'X-Api-Key': _key,
        'Authorization': 'Basic Y2FuYXJ5dXNlcjpjYW5hcnlwYXNz',
      },
    ),
  )..httpClientAdapter = adapter;
  dio.interceptors.add(
    LoggingInterceptor(out.logger(min: min), pathPrefix: prefix),
  );
  return dio;
}

ResponseBody _json(String body, [int status = 200]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  group('routeShape', () {
    test('keeps route words and replaces ids, hashes, titles and files', () {
      expect(routeShape('/api/v3/movie/123'), '/api/v3/movie/{id}');
      expect(routeShape('/api/v3/movie'), '/api/v3/movie');
      expect(routeShape('api/v3/queue/status'), '/api/v3/queue/status');
      expect(
        routeShape('/api/v2/torrents/${'a' * 40}'),
        '/api/v2/torrents/{id}',
      );
      expect(
        routeShape('/MediaCover/12/poster-500.jpg'),
        '/MediaCover/{id}/poster-500.jpg',
      );
      expect(
        routeShape('/MediaCoverProxy/${'b' * 64}/${'c' * 32}.jpg'),
        '/MediaCoverProxy/{id}/{file}',
      );
      expect(routeShape('/x/Canary%20Movie'), '/x/{id}');
      expect(routeShape('/x/canary-movie-2020'), '/x/{id}');
    });

    test('drops host, query, fragment and the path prefix', () {
      expect(
        routeShape(
          'https://$_host:7878/radarr/api/v3/movie/5?apikey=$_key#f',
          pathPrefix: '/radarr',
        ),
        '/api/v3/movie/{id}',
      );
      expect(routeShape('/a/b?term=$_title'), '/a/b');
      // A prefix only matches whole segments.
      expect(routeShape('/radarrx/api', pathPrefix: '/radarr'), '/radarrx/api');
    });

    test('long paths are cut', () {
      expect(
        routeShape('/a/b/c/d/e/f/g/h/i/j/k').split('/').length,
        lessThan(11),
      );
    });
  });

  group('LoggingInterceptor', () {
    test('logs success at debug: method, route, status and duration', () async {
      final out = _Lines();
      final dio = _dio(out, StubAdapter((o) => _json('[]')));
      await dio.get<Object>('/api/v3/movie/42', queryParameters: {'t': _title});
      expect(out.lines, hasLength(1));
      expect(out.lines.single.$1, LogLevel.debug);
      expect(
        out.lines.single.$2,
        matches(RegExp(r'^GET /api/v3/movie/\{id\} -> 200, \d+ms$')),
      );
    });

    test('logs failures at warning with the category and status', () async {
      final out = _Lines();
      final dio = _dio(out, StubAdapter((o) => _json('', 401)));
      await expectLater(
        dio.get<Object>('/api/v3/movie'),
        throwsA(isA<DioException>()),
      );
      expect(out.lines.single.$1, LogLevel.warning);
      expect(
        out.lines.single.$2,
        matches(
          RegExp(
            r'^GET /api/v3/movie failed category=auth_failed status=401, \d+ms$',
          ),
        ),
      );
    });

    test('a connection failure has a category and no status', () async {
      final out = _Lines();
      final dio = _dio(
        out,
        StubAdapter(
          (o) => throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: o,
          ),
        ),
      );
      await expectLater(
        dio.post<Object>('/api/v3/command'),
        throwsA(isA<DioException>()),
      );
      expect(
        out.lines.single.$2,
        startsWith('POST /api/v3/command failed category=timeout'),
      );
      expect(out.lines.single.$2, isNot(contains('status')));
    });

    test('debug lines are not produced below the debug level', () async {
      final out = _Lines();
      final dio = _dio(
        out,
        StubAdapter((o) => _json('[]')),
        min: LogLevel.info,
      );
      await dio.get<Object>('/api/v3/movie');
      expect(out.lines, isEmpty);
    });

    test('debug lines reach the opt-in log while it is on', () async {
      final diagnostics = DiagnosticsLog()
        ..enabled = true
        ..level = LogLevel.debug;
      final dio = Dio(BaseOptions(baseUrl: 'https://$_host'))
        ..httpClientAdapter = StubAdapter((o) => _json('[]'));
      dio.interceptors.add(
        LoggingInterceptor(
          AppLogger(diagnostics: diagnostics, sink: (_, _) {}),
        ),
      );
      await dio.get<Object>('/api/v3/movie');
      expect(diagnostics.length, 1);
      expect(diagnostics.entryAt(0).level, LogLevel.debug);
    });

    test(
      'canary: no key, host, port, title, userinfo or header leaks',
      () async {
        final out = _Lines();
        for (final status in [200, 401, 404, 500]) {
          final dio = _dio(
            out,
            StubAdapter((o) => _json('{"title":"$_title"}', status)),
            prefix: '/radarr',
          );
          for (final path in [
            '/api/v3/movie/lookup?term=$_title',
            '/api/v3/movie/7?apikey=$_key',
            'https://$_user:$_pass@$_host/radarr/api/v3/movie/$_title?x=$_key',
          ]) {
            try {
              await dio.get<Object>(
                path,
                data: {'title': _title, 'password': _pass},
                queryParameters: {'apikey': _key, 'term': _title},
              );
            } on DioException {
              // Failures are logged too.
            }
          }
        }
        expect(out.lines, isNotEmpty);
        for (final secret in [
          _host,
          '7878',
          _key,
          'CANARY',
          _user,
          _pass,
          _title,
          'Canary',
          'apikey',
          'Basic',
          'Y2FuYXJ5',
          '@',
          '?',
          'radarr/',
        ]) {
          expect(out.all, isNot(contains(secret)), reason: secret);
        }
      },
    );

    test('of(dio) finds the attached interceptor', () {
      final dio = Dio();
      expect(LoggingInterceptor.of(dio), isNull);
      final i = LoggingInterceptor(AppLogger(sink: (_, _) {}));
      dio.interceptors.add(i);
      expect(LoggingInterceptor.of(dio), same(i));
    });

    test('artwork rejection logs the route, status and a coarse type', () {
      final out = _Lines();
      LoggingInterceptor(out.logger(), pathPrefix: '/radarr').artworkRejected(
        Uri.parse('https://$_host/radarr/MediaCover/9/poster.jpg?lastWrite=1'),
        status: 200,
        contentType: 'text/html; charset=$_title',
        isEmpty: false,
      );
      expect(
        out.lines.single.$2,
        'artwork GET /MediaCover/{id}/poster.jpg rejected '
        'category=not_an_image status=200 type=html',
      );
      expect(out.lines.single.$1, LogLevel.warning);
      expect(out.all, isNot(contains(_host)));
      expect(out.all, isNot(contains(_title)));
    });
  });
}
