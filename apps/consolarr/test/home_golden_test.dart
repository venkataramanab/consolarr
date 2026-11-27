// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/home/home_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

const _cases = {
  'home_en_dark_360x800': HarnessVariant(
    size: Size(360, 800),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.dark,
  ),
  'home_ar_light_320x568_x2': HarnessVariant(
    size: Size(320, 568),
    textScale: 2,
    locale: Locale('ar'),
    brightness: Brightness.light,
  ),
  'home_en_XA_dark_412x915': HarnessVariant(
    size: Size(412, 915),
    textScale: 1,
    locale: Locale('en', 'XA'),
    brightness: Brightness.dark,
  ),
};

void main() {
  _cases.forEach((name, variant) {
    testWidgets('golden: $name', (tester) async {
      applyVariantView(tester, variant);
      await tester.pumpWidget(harnessApp(variant, const HomeScreen()));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  });
}
