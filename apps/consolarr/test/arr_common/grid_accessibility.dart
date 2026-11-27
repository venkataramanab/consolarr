// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/arr_common/presentation/calendar_month_grid.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

/// Accessibility of a screen with the month grid.
///
/// Labels and contrast always apply in full. Below about 368dp seven cells
/// cannot all be 48dp wide, so the grid's cells are checked against the
/// documented 40dp x 48dp ([ArrMonthGrid.minCellWidth] and
/// [ArrMonthGrid.minCellHeight]) instead of the 48dp x 48dp guideline; from
/// 368dp up the standard guideline applies.
Future<void> expectGridAccessible(WidgetTester tester, HarnessVariant v) async {
  await expectLabeledTapTargets(tester);
  await expectTextContrast(tester);
  if (v.size.width >= 368) {
    await expectTapTargets(tester);
    return;
  }
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    await expectLater(
      tester,
      meetsGuideline(
        const MinimumTapTargetGuideline(
          size: Size(ArrMonthGrid.minCellWidth, ArrMonthGrid.minCellHeight),
          link: 'docs/contributing/definition-of-done.md',
        ),
      ),
    );
  } finally {
    handle.dispose();
  }
}
