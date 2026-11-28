// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/shared/logging/log_events.dart';
import 'package:consolarr/shared/logging/logging_interceptor.dart';
import 'package:consolarr/shared/logging/route_shape.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

/// The shared bundle (and the write-time pass) runs every line through this.
/// A line the scrubber changes is a line that reads as `[REDACTED]` for the
/// person reading the bundle, so every line we can produce must survive it.
const _scrubber = DiagnosticsScrubber();

/// Route literals the clients actually use: `api/v3/movie/$id`, `json`, ...
/// Read from the clients' sources, so a new endpoint cannot slip past the
/// vocabulary unnoticed.
List<String> _clientRoutes() {
  final found = <String>{};
  final literal = RegExp(
    r"'((?:api|transmission|json|MediaCover)(?:/[^']*)?)'",
  );
  for (final root in ['../../packages', 'lib']) {
    for (final f in Directory(root).listSync(recursive: true)) {
      if (f is! File ||
          !f.path.endsWith('.dart') ||
          f.path.contains('/test/') ||
          f.path.contains('/.dart_tool/')) {
        continue;
      }
      for (final m in literal.allMatches(f.readAsStringSync())) {
        found.add(m[1]!.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '7'));
      }
    }
  }
  return found.toList()..sort();
}

class _Lines {
  final List<String> lines = [];
  AppLogger get logger =>
      AppLogger(sink: (_, m) => lines.add(m), minLevel: LogLevel.debug);
}

void main() {
  final routes = _clientRoutes();

  test('the clients use routes at all (the scan finds them)', () {
    expect(routes, contains('api/v3/movie'));
    expect(routes, contains('api/v2/torrents/info'));
    expect(routes, contains('transmission/rpc'));
    expect(routes, contains('json'));
    expect(routes.length, greaterThan(30));
  });

  test('every route a client uses keeps its words: nothing becomes {seg}', () {
    for (final r in routes) {
      final shape = routeShape('/$r');
      expect(shape, isNot(contains('{seg}')), reason: r);
      expect(shape, isNot(contains('{more}')), reason: r);
    }
  });

  test('every request line the interceptor can write survives the scrubber '
      'unchanged', () async {
    final out = _Lines();
    final statuses = [200, 204, 301, 400, 401, 403, 404, 429, 500, 503];
    for (final prefix in ['', '/radarr', '/a/b']) {
      for (final route in routes) {
        for (final method in ['GET', 'POST', 'PUT', 'DELETE']) {
          for (final status in statuses) {
            final dio = Dio(BaseOptions(baseUrl: 'https://example.test$prefix'))
              ..httpClientAdapter = StubAdapter(
                (o) => ResponseBody.fromString('', status),
              )
              ..interceptors.add(
                LoggingInterceptor(out.logger, pathPrefix: prefix),
              );
            try {
              await dio.request<Object>(
                route,
                options: Options(method: method),
              );
            } on DioException {
              // Logged as a failure.
            }
          }
        }
      }
    }
    // Every transport failure, on a bare route and on an id route.
    for (final type in DioExceptionType.values) {
      for (final route in ['api/v3/movie', 'api/v3/movie/42', 'json']) {
        final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = StubAdapter(
            (o) => throw DioException(requestOptions: o, type: type),
          )
          ..interceptors.add(LoggingInterceptor(out.logger));
        try {
          await dio.get<Object>(route);
        } on DioException {
          // Logged as a failure.
        }
      }
    }
    expect(out.lines.length, greaterThan(500));
    for (final line in out.lines) {
      expect(_scrubber.scrub(line), line, reason: line);
      expect(line, isNot(contains('/')), reason: line);
      expect(line, isNot(contains('.')), reason: line);
    }
  });

  test('hostile paths still give lines the scrubber leaves alone', () async {
    final out = _Lines();
    for (final path in [
      '/api/v3/series/SecretTitleQZXW',
      '/api/v3/movie/lookup?term=Secret%20Title',
      '/api/v3/series/the-secret-title-2020',
      '/MediaCover/7/Secret_Title.jpg',
      '/MediaCoverProxy/${'a' * 64}/${'b' * 32}.jpg',
      '/api/v2/torrents/info/${'c' * 40}',
      '/x.y.z/a:b/user@host.test',
      '/api/v3/movie/${'9' * 30}',
    ]) {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = StubAdapter(
          (o) => ResponseBody.fromString('', 404),
        )
        ..interceptors.add(LoggingInterceptor(out.logger));
      try {
        await dio.get<Object>(path);
      } on DioException {
        // Logged as a failure.
      }
    }
    final all = out.lines.join('\n');
    for (final leak in ['Secret', 'secret', 'Title', 'QZXW', '2020', 'user']) {
      expect(all, isNot(contains(leak)), reason: leak);
    }
    for (final line in out.lines) {
      expect(_scrubber.scrub(line), line, reason: line);
    }
  });

  test('artwork rejection lines survive the scrubber unchanged', () {
    final out = _Lines();
    final interceptor = LoggingInterceptor(out.logger, pathPrefix: '/radarr');
    for (final file in ['poster.jpg', 'poster-500.jpg', 'fanart-1280.jpg']) {
      for (final (type, empty) in [
        ('text/html', false),
        ('application/json', false),
        ('image/svg+xml', false),
        (null, true),
      ]) {
        interceptor.artworkRejected(
          Uri.parse('https://example.test/radarr/MediaCover/9/$file?h=1'),
          status: 200,
          contentType: type,
          isEmpty: empty,
        );
      }
    }
    interceptor.artworkRejected(
      Uri.parse(
        'https://example.test/radarr/MediaCoverProxy/${'a' * 64}/x.jpg',
      ),
      status: null,
      contentType: null,
      isEmpty: true,
    );
    expect(out.lines, isNotEmpty);
    for (final line in out.lines) {
      expect(_scrubber.scrub(line), line, reason: line);
      expect(line, isNot(contains('/')), reason: line);
      expect(line, isNot(contains('.')), reason: line);
    }
  });

  test('every app-level log point survives the scrubber unchanged', () {
    final out = _Lines();
    final logger = out.logger;
    for (final kind in ServiceKind.values) {
      logServerSwitch(logger, kind);
      logNeedsCredentials(logger, kind);
      logConnectionTest(logger, kind, null);
      for (final category in ErrorCategory.values) {
        logConnectionTest(logger, kind, AppError(category));
      }
    }
    for (final area in OfflineArea.values) {
      for (final category in ErrorCategory.values) {
        logOfflineFallback(logger, area, AppError(category));
      }
    }
    expect(out.lines, isNotEmpty);
    for (final line in out.lines) {
      expect(_scrubber.scrub(line), line, reason: line);
    }
  });
}
