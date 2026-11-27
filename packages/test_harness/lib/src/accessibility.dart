// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

/// Android tap targets are at least 48x48 dp.
Future<void> expectTapTargets(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    // Semantics are only built on the next frame after being enabled; without
    // this pump the guidelines would pass vacuously on an empty tree.
    await tester.pump();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  } finally {
    handle.dispose();
  }
}

/// Every tappable element has a semantic label.
Future<void> expectLabeledTapTargets(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    // Semantics are only built on the next frame after being enabled; without
    // this pump the guidelines would pass vacuously on an empty tree.
    await tester.pump();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  } finally {
    handle.dispose();
  }
}

/// Text meets the WCAG contrast guideline against what is rendered behind it.
Future<void> expectTextContrast(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    // Semantics are only built on the next frame after being enabled; without
    // this pump the guidelines would pass vacuously on an empty tree.
    await tester.pump();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  } finally {
    handle.dispose();
  }
}

/// All three guidelines.
Future<void> expectAccessible(WidgetTester tester) async {
  await expectTapTargets(tester);
  await expectLabeledTapTargets(tester);
  await expectTextContrast(tester);
}
