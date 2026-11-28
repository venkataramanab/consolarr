// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/presentation/onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

/// Every onboarding step under the full matrix: 320x568 and 412x915, locales
/// en / en_XA / ar, text scale 1.0 and 2.0, light and dark (24 variants per
/// step), with no overflow and the accessibility guidelines.
final _matrix = harnessMatrix(sizes: const [Size(320, 568), Size(412, 915)]);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _top(WidgetTester tester) async {
  // A scroll offset left over from a tap would clip the first widgets.
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _check(WidgetTester tester, HarnessVariant v) async {
  await _top(tester);
  expectNoFrameworkExceptions(tester);
  await expectTapTargets(tester);
  await expectLabeledTapTargets(tester);
  await expectTextContrastWhileScrolling(tester);
}

Finder _fieldAt(int index) => find.byType(TextField).at(index);

Future<void> _toChoose(WidgetTester tester) async {
  await _tap(tester, find.byType(FilledButton).first);
}

Future<void> _toDetails(WidgetTester tester) async {
  await _toChoose(tester);
  await _tap(tester, find.byType(ListTile).first);
  await _top(tester);
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(_fieldAt(0), 'Example Sonarr');
  await tester.enterText(_fieldAt(1), 'https://sonarr.example');
  await tester.pumpAndSettle();
}

/// The final step: the details are valid, the connection is not tested yet.
Future<void> _toTest(WidgetTester tester) async {
  await _toDetails(tester);
  await _fill(tester);
  await _tap(tester, find.byType(FilledButton).last);
  await _top(tester);
}

void _step(String name, Future<void> Function(WidgetTester tester) reach) {
  testWidgets('$name: full matrix', (tester) async {
    expect(_matrix, hasLength(24));
    await pumpMatrix(
      tester,
      (v) => UiHarness().app(v, const OnboardingScreen()),
      variants: _matrix,
      verify: (v) async {
        await reach(tester);
        try {
          await _check(tester, v);
        } on TestFailure catch (e) {
          fail('${v.label}: ${e.message}');
        }
      },
    );
  });
}

void main() {
  _step('welcome', (tester) async {});
  _step('choose service', _toChoose);
  _step('details', _toDetails);
  _step('details with validation errors', (tester) async {
    await _toDetails(tester);
    await _tap(tester, find.byType(FilledButton).last);
    await _top(tester);
  });
  _step('test and finish', _toTest);
}
