// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/arr_common/presentation/sort_filter_chip_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

Widget _bar(
  HarnessVariant v, {
  List<ArrActiveFilter> filters = const [],
  void Function(String)? onRemove,
  VoidCallback? onSort,
  VoidCallback? onFilter,
  VoidCallback? onClear,
}) => harnessApp(
  v,
  Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: ArrSortFilterBar(
        sortLabel: 'Sort: Title',
        sortSemanticsLabel: 'Sort by Title, ascending',
        ascending: true,
        onSort: onSort ?? () {},
        filterLabel: 'Filter (${filters.length})',
        filterSemanticsLabel: 'Filter',
        onFilter: onFilter ?? () {},
        activeFilters: filters,
        onRemoveFilter: onRemove ?? (_) {},
        clearAllLabel: 'Clear all',
        onClearAll: onClear,
      ),
    ),
  ),
);

const _phone = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

const _filters = [
  ArrActiveFilter(
    id: 'a',
    label: 'Monitored',
    removeLabel: 'Remove filter: Monitored',
  ),
  ArrActiveFilter(id: 'b', label: 'Ended', removeLabel: 'Remove filter: Ended'),
];

void main() {
  testWidgets('sort and filter buttons call back', (tester) async {
    var sort = 0;
    var filter = 0;
    applyVariantView(tester, _phone);
    await tester.pumpWidget(
      _bar(_phone, onSort: () => sort++, onFilter: () => filter++),
    );
    await tester.tap(find.text('Sort: Title'));
    await tester.tap(find.text('Filter (0)'));
    expect((sort, filter), (1, 1));
  });

  testWidgets('active filters are chips with a named remove action', (
    tester,
  ) async {
    final removed = <String>[];
    var cleared = 0;
    applyVariantView(tester, _phone);
    await tester.pumpWidget(
      _bar(
        _phone,
        filters: _filters,
        onRemove: removed.add,
        onClear: () => cleared++,
      ),
    );
    expect(find.text('Monitored'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove filter: Ended'));
    await tester.tap(find.text('Clear all'));
    expect(removed, ['b']);
    expect(cleared, 1);
  });

  testWidgets('no chips and no clear button without active filters', (
    tester,
  ) async {
    applyVariantView(tester, _phone);
    await tester.pumpWidget(_bar(_phone, onClear: () {}));
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('accessible and without overflow, with and without filters', (
    tester,
  ) async {
    for (final f in [<ArrActiveFilter>[], _filters]) {
      await pumpMatrix(
        tester,
        (v) => _bar(v, filters: f, onClear: () {}),
        variants: harnessMatrix(
          sizes: const [Size(320, 568), Size(412, 915)],
          textScales: const [1, 2],
          brightnesses: const [Brightness.dark],
        ),
        verify: (v) => expectAccessible(tester),
      );
    }
  });
}
