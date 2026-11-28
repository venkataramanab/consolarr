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

  group('expectTextContrast(skipLabels)', () {
    const low = ColoredBox(
      color: Color(0xFF777777),
      child: Column(
        children: [
          Text(
            'Low contrast', // ignore: consolarr_no_ui_string -- fixture
            style: TextStyle(color: Color(0xFF7C7C7C), fontSize: 24),
          ),
          Text(
            'Also low', // ignore: consolarr_no_ui_string -- fixture
            style: TextStyle(color: Color(0xFF7C7C7C), fontSize: 24),
          ),
        ],
      ),
    );

    testWidgets('skips only the node whose label is named', (tester) async {
      await _pump(tester, low);
      // One named node is skipped, the other still fails.
      await expectTestFailure(
        () => expectTextContrast(tester, skipLabels: {'Low contrast'}),
      );
      // Both named: nothing left to fail.
      await expectTextContrast(
        tester,
        skipLabels: {'Low contrast', 'Also low'},
      );
    });

    testWidgets('an unrelated label skips nothing', (tester) async {
      await _pump(tester, low);
      await expectTestFailure(
        () => expectTextContrast(tester, skipLabels: {'Something else'}),
      );
    });
  });

  group('scrolled content', () {
    Widget list({bool bad = false}) => ListView(
      children: [
        for (var i = 0; i < 40; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Text(
              'Row $i', // ignore: consolarr_no_ui_string -- fixture
              style: TextStyle(
                fontSize: 24,
                color: bad && i == 30
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFFFFFFF),
              ),
            ),
          ),
      ],
    );

    testWidgets('clippedLabels names the rows the viewport cuts', (
      tester,
    ) async {
      await _pump(tester, list());
      final handle = tester.ensureSemantics();
      await tester.pump();
      final clipped = clippedLabels(tester);
      handle.dispose();
      expect(clipped, isNotEmpty);
      expect(clipped, isNot(contains('Row 0')));
    });

    testWidgets('a bad row far below the fold is found while scrolling', (
      tester,
    ) async {
      await _pump(tester, list(bad: true));
      // Top of the list only: the bad row is not on screen, so this passes.
      await expectTextContrast(tester);
      await expectTestFailure(() => expectTextContrastWhileScrolling(tester));
    });

    testWidgets('a good list passes while scrolling, clipped rows excepted', (
      tester,
    ) async {
      await _pump(tester, list());
      await expectTextContrastWhileScrolling(tester);
    });
  });
}
