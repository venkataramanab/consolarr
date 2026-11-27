// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

class _Artwork extends ArtworkSource {
  _Artwork() : super(dio: Dio(), api: FakeSonarrApi());

  @override
  ImageProvider? poster(SonarrSeries series) => MemoryImage(_png);
}

void main() {
  testWidgets('grid posters decode at tile width (ResizeImage), not at full '
      'size', (tester) async {
    const variant = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, variant);
    await tester.pumpWidget(
      libraryApp(
        variant,
        notifier: FakeLibraryNotifier(dataState(fakeSeriesList(12))),
        artwork: _Artwork(),
      ),
    );
    await tester.pump();
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty);
    final dpr = tester.view.devicePixelRatio;
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      expect(image.image, isA<ResizeImage>());
      final resize = image.image as ResizeImage;
      final tileWidth = (element.renderObject! as RenderBox).size.width;
      expect(resize.width, (tileWidth * dpr).round());
      expect(resize.height, isNull);
      expect(resize.width, lessThanOrEqualTo(4096));
    }
  });
}
