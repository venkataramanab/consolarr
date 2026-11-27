// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/arr_common/presentation/calendar_month_grid.dart';
import 'package:consolarr/features/arr_common/presentation/group_header_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'grid_accessibility.dart';

const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

Widget _grid(
  HarnessVariant v, {
  int year = 2026,
  int month = 5,
  int firstWeekday = 0,
  Map<int, int> counts = const {3: 2, 10: 1},
  int? selected,
  int? today = 1,
  ValueChanged<int>? onSelect,
}) => harnessApp(
  v,
  Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: ArrMonthGrid(
        year: year,
        month: month,
        firstWeekday: firstWeekday,
        weekdayLabels: _weekdays,
        counts: counts,
        today: today,
        selected: selected,
        todayMarker: 'today',
        dayLabel: (d, c) => 'day $d, $c items',
        dayText: (d) => '$d',
        onSelect: onSelect ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('every day of the month is a labelled button, none outside it', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => _grid(v),
      variants: tabStressVariants,
      verify: (v) async {
        expect(find.bySemanticsLabel(RegExp(r'^day \d+,')), findsNWidgets(31));
        await expectGridAccessible(tester, v);
      },
    );
  });

  testWidgets('320dp fits seven cells without sideways scrolling', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => _grid(v),
      // The harness reports an overflow as a failure, so none may occur.
      variants: harnessMatrix(
        sizes: const [Size(320, 568)],
        brightnesses: const [Brightness.dark],
      ),
      verify: (v) async {
        expect(find.byType(SingleChildScrollView), findsNothing);
        final grid = tester.getRect(find.byType(ArrMonthGrid));
        expect(grid.right, lessThanOrEqualTo(320));
        for (final cell in tester.widgetList<InkWell>(find.byType(InkWell))) {
          expect(cell.onTap, isNotNull);
        }
        final first = tester.getSize(find.byType(InkWell).first);
        expect(first.width, greaterThanOrEqualTo(ArrMonthGrid.minCellWidth));
        expect(first.height, greaterThanOrEqualTo(ArrMonthGrid.minCellHeight));
        // At large text the cell grows instead of clipping its digits.
        if (v.textScale == 2.0) {
          expect(first.height, greaterThan(ArrMonthGrid.minCellHeight));
        }
        await expectGridAccessible(tester, v);
      },
    );
  });

  testWidgets('narrower than 280dp the grid scrolls instead of shrinking', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(280, 568),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(_grid(v));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('February of a leap year has 29 days', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _grid(v, year: 2028, month: 2, counts: const {}, today: null),
      variants: [tabStressVariants.first],
      verify: (v) async {
        expect(find.bySemanticsLabel(RegExp(r'^day \d+,')), findsNWidgets(29));
      },
    );
  });

  testWidgets('tapping a day reports it; today and selection are announced', (
    tester,
  ) async {
    int? picked;
    final v = tabStressVariants.first;
    applyVariantView(tester, v);
    await tester.pumpWidget(
      _grid(v, selected: 10, onSelect: (d) => picked = d),
    );
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('day 1, 0 items, today'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('day 10, 1 items')),
      matchesSemantics(
        label: 'day 10, 1 items',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasEnabledState: false,
        isFocusable: false,
      ),
    );
    handle.dispose();
    await tester.tap(find.bySemanticsLabel('day 3, 2 items'));
    expect(picked, 3);
  });

  testWidgets('week start shifts the first column', (tester) async {
    final v = tabStressVariants.first;
    applyVariantView(tester, v);
    // 1 May 2026 is a Friday: with Sunday first it sits in column 6, with
    // Monday first in column 5.
    await tester.pumpWidget(_grid(v));
    await tester.pumpAndSettle();
    final sunday = tester
        .getTopLeft(find.bySemanticsLabel('day 1, 0 items, today'))
        .dx;
    await tester.pumpWidget(_grid(v, firstWeekday: 1));
    await tester.pumpAndSettle();
    final monday = tester
        .getTopLeft(find.bySemanticsLabel('day 1, 0 items, today'))
        .dx;
    expect(sunday, greaterThan(monday));
  });

  testWidgets('group header: state, label and tap', (tester) async {
    var toggles = 0;
    await pumpMatrix(
      tester,
      (v) => harnessApp(
        v,
        Scaffold(
          body: ArrGroupHeader(
            title: 'Example Show ${'Long ' * 10}',
            countText: '3 episodes',
            expanded: true,
            onToggle: () => toggles++,
            semanticsLabel: 'Show episodes of Example',
          ),
        ),
      ),
      variants: tabStressVariants,
      verify: (v) => expectAccessible(tester),
    );
    await tester.tap(find.byType(ArrGroupHeader));
    expect(toggles, 1);
  });
}

/// Smallest phone and a large one, every locale and both text scales.
final tabStressVariants = harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  brightnesses: const [Brightness.dark],
);
