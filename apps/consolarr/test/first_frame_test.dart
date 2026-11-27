// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

void main() {
  testWidgets('no network or database access before the first frame', (
    tester,
  ) async {
    await expectNoIoBeforeFirstFrame(
      tester,
      const ProviderScope(child: ConsolarrApp()),
    );
    // And the first frame really was produced.
    expect(find.byType(ConsolarrApp), findsOneWidget);
  });
}
