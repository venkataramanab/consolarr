// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/shared/logging/logging_interceptor.dart';
import 'package:design_system/design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

const _host = 'radarr-canary.invalid';

final _movie = RadarrMovie.fromJson(const {
  'id': 7,
  'title': 'Canary Movie Title',
  'sortTitle': 'canary movie title',
  'year': 2024,
  'status': 'released',
  'monitored': true,
  'images': [
    {'coverType': 'poster', 'url': '/radarr/MediaCover/7/poster.jpg?h=abc123'},
  ],
});

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 8, 12),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(8, 12);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _Rig {
  _Rig(this.reply) {
    diagnostics = DiagnosticsLog()
      ..enabled = true
      ..level = LogLevel.debug;
    dio = Dio(BaseOptions(baseUrl: 'https://$_host:7878/radarr'))
      ..options.headers['X-Api-Key'] = 'test-key-CANARY0000'
      ..httpClientAdapter = StubAdapter((o) {
        requests.add(o.uri.path);
        return reply(o);
      });
    dio.interceptors.add(
      LoggingInterceptor(
        AppLogger(diagnostics: diagnostics, sink: (_, _) {}),
        pathPrefix: '/radarr',
      ),
    );
    source = ArtworkSource(
      dio: dio,
      api: RadarrClient(
        dio: dio,
        parseRunner: <T>(T Function() c) async => c(),
      ),
    );
  }

  final ResponseBody Function(RequestOptions) reply;
  final List<String> requests = [];
  late final DiagnosticsLog diagnostics;
  late final Dio dio;
  late final ArtworkSource source;

  List<String> get lines => [
    for (var i = 0; i < diagnostics.length; i++) diagnostics.entryAt(i).message,
  ];
}

ResponseBody _status(int code) => ResponseBody.fromString('', code);

Future<Object?> _resolveError(ImageProvider provider) {
  final done = Completer<Object?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? st) {
      if (!done.isCompleted) done.complete(error);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

void main() {
  testWidgets('a 404 poster logs a diagnostics entry and shows the '
      'placeholder without a crash', (tester) async {
    final rig = _Rig((_) => _status(404));
    // Image loading is real async work: build and wait outside the fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: movieArtwork(rig.source, _movie, 100)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ArtworkPlaceholder), findsOneWidget);
    // The plain poster, then its resized variant (also 404): two failures.
    expect(rig.requests, [
      '/radarr/MediaCover/7/poster.jpg',
      '/radarr/MediaCover/7/poster-500.jpg',
    ]);
    expect(
      rig.lines,
      everyElement(
        matches(
          RegExp(
            r'^GET /MediaCover/\{id\}/poster(-500)?\.jpg failed '
            r'category=not_found status=404, \d+ms$',
          ),
        ),
      ),
    );
    expect(rig.lines, hasLength(2));
    final all = rig.lines.join('\n');
    for (final secret in [_host, '7878', 'CANARY', 'abc123', 'Canary', '?']) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('a 404 poster is retried once with the resized variant', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final png = await _png();
      final rig = _Rig(
        (o) => o.uri.path.endsWith('poster-500.jpg')
            ? ResponseBody.fromBytes(png, 200)
            : _status(404),
      );
      final error = await _resolveError(rig.source.poster(_movie)!);
      expect(error, isNull);
      expect(rig.requests, hasLength(2));
      expect(rig.requests.last, '/radarr/MediaCover/7/poster-500.jpg');
      // The plain 404 is still on record, the variant succeeded at debug.
      expect(
        rig.lines,
        contains(
          matches(RegExp(r'^GET /MediaCover/\{id\}/poster\.jpg failed ')),
        ),
      );
      expect(
        rig.lines,
        contains(
          matches(RegExp(r'^GET /MediaCover/\{id\}/poster-500\.jpg -> 200,')),
        ),
      );
    });
  });

  testWidgets('only a 404 is retried; 401 and 500 are not', (tester) async {
    await tester.runAsync(() async {
      for (final status in [401, 500]) {
        final rig = _Rig((_) => _status(status));
        final error = await _resolveError(rig.source.poster(_movie)!);
        expect(error, isA<DioException>());
        expect(rig.requests, hasLength(1), reason: '$status');
        expect(rig.lines.single, contains('status=$status'));
      }
    });
  });

  testWidgets('a 200 that is not an image is logged by route, status and '
      'coarse type', (tester) async {
    await tester.runAsync(() async {
      final rig = _Rig(
        (_) => ResponseBody.fromString(
          '<html>Canary Movie Title login</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      );
      final error = await _resolveError(rig.source.poster(_movie)!);
      expect(error, isA<FormatException>());
      expect(
        rig.lines,
        contains(
          'artwork GET /MediaCover/{id}/poster.jpg rejected '
          'category=not_an_image status=200 type=html',
        ),
      );
      expect(rig.lines.join(), isNot(contains('Canary')));
    });
  });

  testWidgets('a TLS failure is logged with its category', (tester) async {
    await tester.runAsync(() async {
      final rig = _Rig(
        (o) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.badCertificate,
        ),
      );
      final error = await _resolveError(rig.source.poster(_movie)!);
      expect(error, isA<DioException>());
      expect(
        rig.lines.single,
        matches(RegExp(r'poster\.jpg failed category=tls_untrusted')),
      );
    });
  });

  testWidgets('a timeout is logged with its category', (tester) async {
    await tester.runAsync(() async {
      final rig = _Rig(
        (o) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: o,
        ),
      );
      final error = await _resolveError(rig.source.poster(_movie)!);
      expect(error, isA<DioException>());
      expect(
        rig.lines.single,
        matches(RegExp(r'poster\.jpg failed category=timeout')),
      );
    });
  });
}
