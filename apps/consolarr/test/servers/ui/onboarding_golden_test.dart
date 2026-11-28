// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/presentation/onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

const _v = HarnessVariant(
  size: Size(320, 568),
  textScale: 2,
  locale: Locale('ar'),
  brightness: Brightness.light,
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _top(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _golden(WidgetTester tester, String name) async {
  await _top(tester);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/onboarding_${name}_ar_light_320x568_x2.png'),
  );
}

void main() {
  testWidgets('golden: onboarding steps (ar, light, 320x568, scale 2.0)', (
    tester,
  ) async {
    applyVariantView(tester, _v);
    await tester.pumpWidget(UiHarness().app(_v, const OnboardingScreen()));
    await tester.pumpAndSettle();
    await _golden(tester, 'welcome');

    await _tap(tester, find.byType(FilledButton).first);
    await _golden(tester, 'choose');

    await _tap(tester, find.byType(ListTile).first);
    await _top(tester);
    await _tap(tester, find.byType(FilledButton).last);
    await _golden(tester, 'details_errors');

    await tester.enterText(find.byType(TextField).at(0), 'Example Sonarr');
    await tester.enterText(
      find.byType(TextField).at(1),
      'https://sonarr.example',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byType(FilledButton).last);
    await _golden(tester, 'test');
  });
}
