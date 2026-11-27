// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

const _variant = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  applyVariantView(tester, _variant);
  await tester.pumpWidget(harnessApp(_variant, Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accepts a 48dp, labelled button with readable text', (
    tester,
  ) async {
    await _pump(
      tester,
      Center(
        child: IconButton(
          tooltip: 'Add', // ignore: consolarr_no_ui_string -- test fixture
          onPressed: () {},
          icon: const Icon(Icons.add),
        ),
      ),
    );
    await expectTapTargets(tester);
    await expectLabeledTapTargets(tester);
  });

  testWidgets('rejects a tiny tap target', (tester) async {
    await _pump(
      tester,
      Center(
        child: Semantics(
          container: true,
          button: true,
          label: 'Tiny', // ignore: consolarr_no_ui_string -- test fixture
          onTap: () {},
          child: const SizedBox(width: 16, height: 16),
        ),
      ),
    );
    await expectTestFailure(() => expectTapTargets(tester));
  });

  testWidgets('rejects an unlabeled tap target', (tester) async {
    await _pump(
      tester,
      Center(
        child: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
      ),
    );
    await expectTestFailure(() => expectLabeledTapTargets(tester));
  });

  testWidgets('rejects low-contrast text', (tester) async {
    await _pump(
      tester,
      const ColoredBox(
        color: Color(0xFF777777),
        child: Center(
          child: Text(
            'Low contrast', // ignore: consolarr_no_ui_string -- fixture
            style: TextStyle(color: Color(0xFF7C7C7C), fontSize: 24),
          ),
        ),
      ),
    );
    await expectTestFailure(() => expectTextContrast(tester));
  });

  testWidgets('accepts high-contrast text', (tester) async {
    await _pump(
      tester,
      const ColoredBox(
        color: Color(0xFF000000),
        child: Center(
          child: Text(
            'Readable', // ignore: consolarr_no_ui_string -- fixture
            style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 24),
          ),
        ),
      ),
    );
    await expectTextContrast(tester);
  });
}
