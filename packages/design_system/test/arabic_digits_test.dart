// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support/host.dart';

const _ar = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('ar'),
  brightness: Brightness.dark,
);

void main() {
  testWidgets('the filter sheet count is formatted by the locale in ar', (
    tester,
  ) async {
    applyVariantView(tester, _ar);
    await tester.pumpWidget(
      hostApp(
        _ar,
        FilterSheet(
          title: 'Filter',
          sections: const [],
          activeCount: 12,
          clearAllLabel: 'Clear',
          saveAsDefaultLabel: 'Save',
          applyLabel: 'Apply',
          onApply: (selection, save) {},
          onClear: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shown = MaterialLocalizations.of(
      tester.element(find.byType(FilterSheet)),
    ).formatDecimal(12);
    expect(find.text(shown), findsWidgets, reason: 'locale numerals');
  });
}
