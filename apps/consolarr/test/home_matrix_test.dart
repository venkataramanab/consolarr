// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/features/home/home_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

void main() {
  testWidgets('home: no overflow across sizes, scales, locales and themes', (
    tester,
  ) async {
    await pumpMatrix(tester, (v) => harnessApp(v, const HomeScreen()));
  });

  testWidgets('about: no overflow across sizes, scales, locales and themes', (
    tester,
  ) async {
    await pumpMatrix(tester, (v) => harnessApp(v, const AboutScreen()));
  });

  testWidgets(
    'home: accessibility guidelines at text scale 2.0 in ar and en_XA',
    (tester) async {
      await pumpMatrix(
        tester,
        (v) => harnessApp(v, const HomeScreen()),
        variants: harnessMatrix(
          textScales: [2],
          locales: [const Locale('ar'), const Locale('en', 'XA')],
        ),
        verify: (v) async {
          await expectTapTargets(tester);
          await expectLabeledTapTargets(tester);
          await expectTextContrast(tester);
        },
      );
    },
  );

  testWidgets('home: accessibility guidelines at 1.0 in en', (tester) async {
    await pumpMatrix(
      tester,
      (v) => harnessApp(v, const HomeScreen()),
      variants: harnessMatrix(textScales: [1], locales: [const Locale('en')]),
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('home mirrors in a right-to-left locale', (tester) async {
    late TextDirection direction;
    await pumpMatrix(
      tester,
      (v) => harnessApp(
        v,
        Builder(
          builder: (context) {
            direction = Directionality.of(context);
            return const HomeScreen();
          },
        ),
      ),
      variants: harnessMatrix(
        sizes: [const Size(360, 800)],
        textScales: [1],
        locales: [const Locale('ar')],
        brightnesses: [Brightness.dark],
      ),
    );
    expect(direction, TextDirection.rtl);
  });
}
