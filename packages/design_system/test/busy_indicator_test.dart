// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support/host.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  A11yVariant a = A11yVariant.normal,
  bool platformReduceMotion = false,
}) async {
  applyVariantView(tester, _v);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: platformReduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(hostApp(_v, child, a11y: a, scroll: false));
  await tester.pump();
}

const _animating = A11yVariant('animating', reduceMotion: false);

void main() {
  testWidgets('spins when motion is allowed', (tester) async {
    await _pump(
      tester,
      const BusyIndicator(semanticLabel: 'Loading'),
      a: _animating,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.value, isNull, reason: 'indeterminate when animating');
  });

  testWidgets('is static under the in-app reduce-motion setting', (
    tester,
  ) async {
    await _pump(tester, const BusyIndicator(semanticLabel: 'Loading'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('is static under the platform disable-animations flag', (
    tester,
  ) async {
    await _pump(
      tester,
      const BusyIndicator(semanticLabel: 'Loading'),
      a: _animating,
      platformReduceMotion: true,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
  });

  testWidgets('the linear variant follows the same rules', (tester) async {
    await _pump(
      tester,
      const BusyIndicator.linear(semanticLabel: 'Computing'),
      a: _animating,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await _pump(tester, const BusyIndicator.linear(semanticLabel: 'Computing'));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
  });

  testWidgets('carries the caller label and announces only on first show', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const BusyIndicator(semanticLabel: 'Loading series'),
      a: _animating,
    );
    SemanticsNode node() =>
        tester.getSemantics(find.bySemanticsLabel('Loading series'));
    expect(node().label, 'Loading series');
    // After the first frame the live region is dropped: a rebuild must not
    // re-announce.
    await tester.pump();
    await tester.pump();
    expect(
      node().flagsCollection.isLiveRegion,
      isFalse,
      reason: 'no repeated announcements',
    );
    handle.dispose();
  });

  testWidgets('announces as a live region when it first appears', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    applyVariantView(tester, _v);
    await tester.pumpWidget(
      hostApp(
        _v,
        const BusyIndicator(semanticLabel: 'Loading series'),
        a11y: _animating,
        scroll: false,
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Loading series'));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('a decorative indicator (null label) has no semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const BusyIndicator(semanticLabel: null));
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    handle.dispose();
  });
}
