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

RadarrMovie _movieWith(List<String> types) => RadarrMovie.fromJson({
  'id': 7,
  'title': 'Canary Movie Title',
  'sortTitle': 'canary movie title',
  'year': 2024,
  'status': 'released',
  'monitored': true,
  'images': [
    for (final t in types)
      {'coverType': t, 'url': '/radarr/MediaCover/7/$t.jpg?h=abc123'},
  ],
});

final _movie = _movieWith(['poster']);

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

  List<LogLevel> get levels => [
    for (var i = 0; i < diagnostics.length; i++) diagnostics.entryAt(i).level,
  ];

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
  testWidgets('a poster that is missing everywhere shows the placeholder and '
      'logs one debug line for the whole attempt', (tester) async {
    final rig = _Rig((_) => _status(404));
    await tester.runAsync(() async {
      final provider = ResizeImage(rig.source.poster(_movie)!, width: 100);
      // The widget below resolves an equal provider, so it shares this load:
      // waiting for its error replaces any fixed delay.
      final failed = _resolveError(provider);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: movieArtwork(rig.source, _movie, 100)),
        ),
      );
      expect(await failed, isA<DioException>());
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ArtworkPlaceholder), findsOneWidget);
    // The plain poster, then its resized variant (also 404).
    expect(rig.requests, [
      '/radarr/MediaCover/7/poster.jpg',
      '/radarr/MediaCover/7/poster-500.jpg',
    ]);
    // One line for the attempt, not one per request, and only at debug.
    expect(rig.lines, [
      'artwork GET MediaCover·{id}·poster_jpg missing category=not_found '
          'status=404 tried=2',
    ]);
    expect(rig.levels, [LogLevel.debug]);
    final all = rig.lines.join('\n');
    for (final secret in [_host, '7878', 'CANARY', 'abc123', 'Canary', '?']) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
  });

  testWidgets('a 404 poster is retried once with the resized variant and a '
      'success logs nothing', (tester) async {
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
      expect(rig.lines, isEmpty);
    });
  });

  testWidgets('a poster that is fine logs nothing at all', (tester) async {
    await tester.runAsync(() async {
      final png = await _png();
      final rig = _Rig((_) => ResponseBody.fromBytes(png, 200));
      expect(await _resolveError(rig.source.poster(_movie)!), isNull);
      expect(rig.requests, hasLength(1));
      expect(rig.lines, isEmpty);
    });
  });

  testWidgets('when the poster and its resized variant are 404, cover, then '
      'banner, then fanart are tried in that order', (tester) async {
    await tester.runAsync(() async {
      final png = await _png();
      final movie = _movieWith(['poster', 'cover', 'banner', 'fanart']);
      for (final (works, expected) in [
        ('cover', ['poster.jpg', 'poster-500.jpg', 'cover.jpg']),
        ('banner', ['poster.jpg', 'poster-500.jpg', 'cover.jpg', 'banner.jpg']),
        (
          'fanart',
          [
            'poster.jpg',
            'poster-500.jpg',
            'cover.jpg',
            'banner.jpg',
            'fanart.jpg',
          ],
        ),
      ]) {
        final rig = _Rig(
          (o) => o.uri.path.endsWith('/$works.jpg')
              ? ResponseBody.fromBytes(png, 200)
              : _status(404),
        );
        expect(await _resolveError(rig.source.poster(movie)!), isNull);
        expect(rig.requests, [
          for (final f in expected) '/radarr/MediaCover/7/$f',
        ], reason: works);
        expect(rig.lines, isEmpty, reason: works);
      }
    });
  });

  testWidgets('every image 404: all of them are tried, one line is logged, '
      'and the load fails', (tester) async {
    await tester.runAsync(() async {
      final movie = _movieWith(['poster', 'cover', 'banner', 'fanart']);
      final rig = _Rig((_) => _status(404));
      expect(await _resolveError(rig.source.poster(movie)!), isNotNull);
      expect(rig.requests, hasLength(5));
      expect(rig.lines, [
        'artwork GET MediaCover·{id}·poster_jpg missing category=not_found '
            'status=404 tried=5',
      ]);
    });
  });

  testWidgets('a movie with no poster listed starts from its cover', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final png = await _png();
      final movie = _movieWith(['cover', 'fanart']);
      final rig = _Rig(
        (o) => o.uri.path.endsWith('/fanart.jpg')
            ? ResponseBody.fromBytes(png, 200)
            : _status(404),
      );
      expect(await _resolveError(rig.source.poster(movie)!), isNull);
      expect(rig.requests, [
        '/radarr/MediaCover/7/cover.jpg',
        '/radarr/MediaCover/7/fanart.jpg',
      ]);
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
        expect(rig.levels.single, LogLevel.warning);
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
          'artwork GET MediaCover·{id}·poster_jpg rejected '
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
        matches(RegExp(r'poster_jpg failed category=tls_untrusted')),
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
        matches(RegExp(r'poster_jpg failed category=timeout')),
      );
    });
  });
}
