// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support/samples.dart';

Widget _host(HarnessVariant v, Widget child) => harnessApp(
  v,
  ConsolarrEffectsScope(
    reduceMotion: true,
    child: Scaffold(
      body: SafeArea(child: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  componentSamples().forEach((name, build) {
    testWidgets('$name: no overflow across the full matrix', (tester) async {
      await pumpMatrix(tester, (v) => _host(v, build()));
    });

    testWidgets('$name: accessible at scale 2.0 in ar and en_XA', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => _host(v, build()),
        variants: harnessMatrix(
          textScales: [2],
          locales: [const Locale('ar'), const Locale('en', 'XA')],
        ),
        verify: (v) => expectAccessible(tester),
      );
    });

    testWidgets('$name: accessible at scale 1.0 in en', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _host(v, build()),
        variants: harnessMatrix(textScales: [1], locales: [const Locale('en')]),
        verify: (v) => expectAccessible(tester),
      );
    });
  });
}
