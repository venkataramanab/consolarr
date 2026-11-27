// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:consolarr/src/images/secure_image_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<ui.Image> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? st) {
      if (!done.isCompleted) done.completeError(error, st);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

void main() {
  final recorded = <RequestOptions>[];

  Dio dioReturning(Uint8List bytes) {
    final dio = Dio(BaseOptions(baseUrl: 'https://sonarr.example'))
      ..options.headers['X-Api-Key'] = 'test-key-0000'
      ..httpClientAdapter = StubAdapter((options) {
        recorded.add(options);
        return ResponseBody.fromBytes(bytes, 200);
      });
    return dio;
  }

  setUp(recorded.clear);

  testWidgets('decodes at the requested cache width, not full size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await _png(800, 1200);
      final provider = ResizeImage(
        SecureNetworkImage(
          dio: dioReturning(bytes),
          uri: Uri.parse('https://sonarr.example/MediaCover/1/poster.jpg'),
        ),
        width: 100,
      );
      final image = await _resolve(provider);
      expect(image.width, lessThanOrEqualTo(100));
      expect(image.width, 100);
      expect(image.height, 150);
    });
  });

  testWidgets('the API key travels in a header, never in the URL', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await _png(8, 12);
      final provider = SecureNetworkImage(
        dio: dioReturning(bytes),
        uri: Uri.parse(
          'https://sonarr.example/MediaCover/1/poster.jpg?lastWrite=1',
        ),
      );
      await _resolve(provider);
      expect(recorded, hasLength(1));
      final r = recorded.single;
      expect(r.uri.toString(), isNot(contains('test-key')));
      expect(r.uri.toString(), isNot(contains('apikey')));
      expect(r.headers['X-Api-Key'], 'test-key-0000');
      expect(r.responseType, ResponseType.bytes);
      expect(r.extra[maxResponseBytesKey], SecureNetworkImage.defaultMaxBytes);
    });
  });

  testWidgets('rejects bytes that are not a supported image', (tester) async {
    await tester.runAsync(() async {
      final provider = SecureNetworkImage(
        dio: dioReturning(Uint8List.fromList('<html>hello</html>'.codeUnits)),
        uri: Uri.parse('https://sonarr.example/MediaCover/1/poster.jpg'),
      );
      await expectLater(_resolve(provider), throwsA(isA<FormatException>()));
    });
  });

  test('magic bytes: jpeg, png, webp and gif are accepted, others not', () {
    expect(
      looksLikeSupportedImage(Uint8List.fromList([0xFF, 0xD8, 0xFF, 1])),
      isTrue,
    );
    expect(
      looksLikeSupportedImage(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      isTrue,
    );
    expect(
      looksLikeSupportedImage(Uint8List.fromList('GIF89a'.codeUnits)),
      isTrue,
    );
    expect(
      looksLikeSupportedImage(
        Uint8List.fromList([
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
        ]),
      ),
      isTrue,
    );
    expect(
      looksLikeSupportedImage(Uint8List.fromList('<svg/>'.codeUnits)),
      isFalse,
    );
    expect(looksLikeSupportedImage(Uint8List(0)), isFalse);
  });

  test('providers for the same uri and client are equal (cache key)', () {
    final dio = Dio();
    final uri = Uri.parse('https://sonarr.example/a.jpg');
    expect(
      SecureNetworkImage(dio: dio, uri: uri),
      SecureNetworkImage(dio: dio, uri: uri),
    );
    expect(
      SecureNetworkImage(dio: dio, uri: uri),
      isNot(SecureNetworkImage(dio: Dio(), uri: uri)),
    );
  });
}
