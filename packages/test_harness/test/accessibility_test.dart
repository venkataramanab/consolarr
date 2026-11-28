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

  group('sampler: reads the glyph colour, not the anti-aliasing grey', () {
    const page = Color(0xFFF2F4F8);
    const ink = Color(0xFF1B1F26);
    const checking = 'Checking'; // ignore: consolarr_no_ui_string -- fixture
    // 12 px wrapped text: its strokes are about one pixel wide, so most inked
    // pixels are blends of ink and page. Judged by the glyph colour, not by
    // the commonest colour, it must still pass.
    const paragraph =
        'Opens the site in your browser with a short summary filled in. '
        'The full text is not put in the address: share the file first and '
        'attach it to the issue.'; // ignore: consolarr_no_ui_string -- fixture

    testWidgets('thin dark text on a light page passes', (tester) async {
      await _pump(
        tester,
        const ColoredBox(
          color: page,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(paragraph, style: TextStyle(color: ink, fontSize: 12)),
          ),
        ),
      );
      await expectTextContrast(tester);
    });

    testWidgets('a neighbour inside the old 4 px margin is not text', (
      tester,
    ) async {
      await _pump(
        tester,
        const ColoredBox(
          color: page,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checking', // ignore: consolarr_no_ui_string -- fixture
                  style: TextStyle(color: ink, fontSize: 12),
                ),
                SizedBox(height: 4),
                SizedBox(
                  width: 120,
                  height: 20,
                  child: ColoredBox(color: Color(0xFF008C8C)),
                ),
              ],
            ),
          ),
        ),
      );
      await expectTextContrast(tester);
    });

    testWidgets('a disabled control with the same text is not judged as the '
        'status line', (tester) async {
      // The status line repeats the button's label, and the status node's box
      // reaches over the button (as it does when a layout gives it spare
      // height). Matching by text and overlap alone judged the disabled
      // button's greyed (exempt) label as if it were the status line.
      await _pump(
        tester,
        ColoredBox(
          color: page,
          child: SizedBox(
            width: 300,
            height: 200,
            child: Stack(
              children: [
                Semantics(
                  liveRegion: true,
                  container: true,
                  child: const Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      checking,
                      style: TextStyle(color: ink, fontSize: 13),
                    ),
                  ),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  child: OutlinedButton(onPressed: null, child: Text(checking)),
                ),
              ],
            ),
          ),
        ),
      );
      await expectTextContrast(tester);
    });

    testWidgets('an enabled control with the same text is still judged', (
      tester,
    ) async {
      await _pump(
        tester,
        ColoredBox(
          color: page,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    checking,
                    style: TextStyle(color: Color(0xFFB4B8C0), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await expectTestFailure(() => expectTextContrast(tester));
    });

    testWidgets('thin text that really is low contrast still fails', (
      tester,
    ) async {
      await _pump(
        tester,
        const ColoredBox(
          color: page,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              paragraph,
              style: TextStyle(color: Color(0xFFB4B8C0), fontSize: 12),
            ),
          ),
        ),
      );
      await expectTestFailure(() => expectTextContrast(tester));
    });
  });

  group('scrolled content', () {
    Widget list({bool bad = false, double pad = 12}) => ListView(
      children: [
        for (var i = 0; i < 40; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: pad, horizontal: 16),
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
      // No row padding, so the fold falls through a line of text (with the
      // padding it can fall in the gap between two rows and clip nothing).
      await _pump(tester, list(pad: 0));
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
