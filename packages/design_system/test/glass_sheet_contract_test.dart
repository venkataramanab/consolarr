// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
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

Future<void> _pump(WidgetTester tester, Widget child) async {
  applyVariantView(tester, _v);
  await tester.pumpWidget(hostApp(_v, child, scroll: false));
  await tester.pumpAndSettle();
}

Widget _opener(Future<Object?> Function(BuildContext) open) => Builder(
  builder: (context) =>
      TextButton(onPressed: () => open(context), child: const Text('open')),
);

void main() {
  group('GlassSheetDetents', () {
    test('named constants and fractions', () {
      expect(GlassSheetDetents.peek.initialFull, isFalse);
      expect(GlassSheetDetents.full.initialFull, isTrue);
      expect(GlassSheetDetents.peek.peekFraction, 0.5);
      expect(GlassSheetDetents.full.fullFraction, 0.92);
      expect(const GlassSheetDetents(peekFraction: 0.6).peekFraction, 0.6);
      expect(const GlassSheetDetents.fullOnly().isSingle, isTrue);
    });
  });

  test('FilterChipOption is FilterChoice', () {
    const FilterChipOption option = FilterChoice(id: 'a', label: 'A');
    expect(option, isA<FilterChoice>());
  });

  group('showGlassSheet bodies', () {
    testWidgets('exactly one of builder and scrollBuilder', (tester) async {
      await _pump(tester, const SizedBox());
      final context = tester.element(find.byType(Scaffold));
      expect(
        () =>
            showGlassSheet<void>(context: context, title: 't', closeLabel: 'c'),
        throwsAssertionError,
      );
      expect(
        () => showGlassSheet<void>(
          context: context,
          title: 't',
          closeLabel: 'c',
          builder: (_) => const SizedBox(),
          scrollBuilder: (_, _) => const SizedBox(),
        ),
        throwsAssertionError,
      );
    });

    testWidgets('scrollBuilder keeps a long list lazy', (tester) async {
      var built = 0;
      await _pump(
        tester,
        _opener(
          (c) => showGlassSheet<void>(
            context: c,
            title: 'Long',
            closeLabel: 'Close',
            detents: GlassSheetDetents.full,
            scrollBuilder: (context, controller) => ListView.builder(
              controller: controller,
              itemCount: 1000,
              itemBuilder: (context, i) {
                built++;
                return SizedBox(height: 48, child: Text('row $i'));
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('row 0'), findsOneWidget);
      expect(built, lessThan(60));
      await tester.drag(find.text('row 0'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('row 0'), findsNothing);
    });
  });

  group('root navigator', () {
    testWidgets('the nav bar behind a sheet is not hit-testable', (
      tester,
    ) async {
      applyVariantView(tester, _v);
      final nestedKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        harnessApp(
          _v,
          Scaffold(
            body: Navigator(
              key: nestedKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => Center(
                  child: _opener(
                    (c) => showGlassSheet<void>(
                      context: c,
                      title: 'Sheet',
                      closeLabel: 'Close',
                      builder: (_) => const Text('body'),
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: TextButton(
              key: const ValueKey('bar'),
              onPressed: () {},
              child: const Text('bar'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bar')).hitTestable(), findsOneWidget);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('body'), findsOneWidget);
      expect(find.byKey(const ValueKey('bar')).hitTestable(), findsNothing);
      // The sheet is on the root navigator, not the nested one.
      expect(nestedKey.currentState!.canPop(), isFalse);
    });
  });

  group('handle', () {
    testWidgets('hit target is at least 48dp and always has a label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        _opener(
          (c) => showGlassSheet<void>(
            context: c,
            title: 'Sheet',
            closeLabel: 'Close',
            builder: (_) => const Text('body'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('glass-sheet-handle'));
      final size = tester.getSize(
        find.descendant(of: handle, matching: find.byType(GestureDetector)),
      );
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(handle).label, isNotEmpty);
      semantics.dispose();
    });
  });
}
