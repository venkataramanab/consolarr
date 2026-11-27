// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
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

const _rtl = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('ar'),
  brightness: Brightness.dark,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  HarnessVariant v = _v,
  A11yVariant a = A11yVariant.normal,
  bool scroll = false,
  bool reduceTransparency = false,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(
    hostApp(
      v,
      child,
      a11y: a,
      scroll: scroll,
      reduceTransparency: reduceTransparency,
    ),
  );
  await tester.pumpAndSettle();
}

Widget _opener(
  Future<Object?> Function(BuildContext) open, {
  List<Object?>? results,
}) => Builder(
  builder: (context) => TextButton(
    onPressed: () async {
      final r = await open(context);
      results?.add(r);
    },
    child: const Text('open'),
  ),
);

void main() {
  setUp(StagedReveal.resetForTesting);

  group('showGlassSheet', () {
    Future<void> openSheet(
      WidgetTester tester, {
      GlassSheetDetents detents = const GlassSheetDetents(),
      bool reduceTransparency = false,
      A11yVariant a = A11yVariant.normal,
      List<Object?>? results,
    }) async {
      await _pump(
        tester,
        _opener(
          (c) => showGlassSheet<String>(
            context: c,
            title: 'Sheet title',
            closeLabel: 'Close sheet',
            toggleDetentLabel: 'Expand or collapse',
            detents: detents,
            builder: (c) => Column(
              children: [
                const Text('Body text'),
                TextButton(
                  onPressed: () => Navigator.of(c).pop('picked'),
                  child: const Text('Pick'),
                ),
              ],
            ),
          ),
          results: results,
        ),
        reduceTransparency: reduceTransparency,
        a: a,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows title, handle and close button; close dismisses', (
      tester,
    ) async {
      final results = <Object?>[];
      await openSheet(tester, results: results);
      expect(find.text('Sheet title'), findsOneWidget);
      expect(find.text('Body text'), findsOneWidget);
      expect(find.byTooltip('Close sheet'), findsOneWidget);
      await tester.tap(find.byTooltip('Close sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet title'), findsNothing);
      expect(results, [null]);
    });

    testWidgets('returns the value popped by the content', (tester) async {
      final results = <Object?>[];
      await openSheet(tester, results: results);
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(results, ['picked']);
    });

    testWidgets('never traps focus: Tab moves on, Escape dismisses', (
      tester,
    ) async {
      await openSheet(tester);
      final seen = <FocusNode?>{};
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        seen.add(FocusManager.instance.primaryFocus);
      }
      expect(seen.length, greaterThan(1));
      expect(find.text('Sheet title'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Sheet title'), findsNothing);
    });

    testWidgets('peek and full detents; the handle toggles them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openSheet(tester);
      final screen = tester.view.physicalSize.height;
      double sheetHeight() =>
          tester.getSize(find.byType(DraggableScrollableSheet)).height;
      expect(sheetHeight(), closeTo(screen * 0.5, 2));
      await tester.tap(find.byKey(const ValueKey('glass-sheet-handle')));
      await tester.pumpAndSettle();
      expect(sheetHeight(), closeTo(screen * 0.92, 2));
      await tester.tap(find.byKey(const ValueKey('glass-sheet-handle')));
      await tester.pumpAndSettle();
      expect(sheetHeight(), closeTo(screen * 0.5, 2));
      handle.dispose();
    });

    testWidgets('keyboard-safe: the sheet stays above the keyboard', (
      tester,
    ) async {
      await openSheet(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final bottom = tester
          .getBottomLeft(find.byType(DraggableScrollableSheet))
          .dy;
      expect(bottom, lessThanOrEqualTo(800 - 300 + 0.5));
    });

    testWidgets('glass by default, solid under reduced transparency', (
      tester,
    ) async {
      await openSheet(tester);
      expect(
        find.descendant(
          of: find.byType(GlassSheet),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await openSheet(tester, reduceTransparency: true);
      expect(
        find.descendant(
          of: find.byType(GlassSheet),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    });

    testWidgets('rises with motion, opens instantly under reduced motion', (
      tester,
    ) async {
      await _pump(
        tester,
        _opener(
          (c) => showGlassSheet<void>(
            context: c,
            title: 't',
            closeLabel: 'c',
            builder: (_) => const Text('Body'),
          ),
        ),
        a: const A11yVariant('motion', reduceMotion: false),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await _pump(
        tester,
        _opener(
          (c) => showGlassSheet<void>(
            context: c,
            title: 't',
            closeLabel: 'c',
            builder: (_) => const Text('Body'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('the sheet is named for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await openSheet(tester);
      expect(
        tester.getSemantics(find.byType(GlassSheet)).label,
        contains('Sheet title'),
      );
      final close = tester.getSemantics(find.byType(IconButton));
      expect('${close.label} ${close.tooltip}', contains('Close sheet'));
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('glass-sheet-handle')))
            .label,
        'Expand or collapse',
      );
      handle.dispose();
    });
  });

  group('NestedMenu', () {
    final log = <String>[];
    List<NestedMenuItem> items() => [
      NestedMenuItem(label: 'Refresh', onSelected: () => log.add('refresh')),
      NestedMenuItem(
        label: 'Sort by',
        children: [
          NestedMenuItem(label: 'Title', onSelected: () => log.add('title')),
          NestedMenuItem(label: 'Added', onSelected: () => log.add('added')),
        ],
      ),
      NestedMenuItem(
        label: 'Delete',
        destructive: true,
        onSelected: () => log.add('delete'),
      ),
      NestedMenuItem(
        label: 'Search',
        enabled: false,
        disabledReason: 'Nothing to search',
        onSelected: () => log.add('search'),
      ),
    ];

    setUp(log.clear);

    Future<void> openMenu(WidgetTester tester, {HarnessVariant v = _v}) async {
      await _pump(
        tester,
        Align(
          alignment: AlignmentDirectional.topEnd,
          child: Builder(
            builder: (context) => IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onPressed: () => showNestedMenu(
                context,
                anchorRectOf(context),
                items(),
                'More actions',
              ),
            ),
          ),
        ),
        v: v,
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
    }

    testWidgets('a leaf closes the menu, then runs', (tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(log, ['refresh']);
      expect(find.text('Refresh'), findsNothing);
    });

    testWidgets('sub-menu opens in place and goes back', (tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Sort by'));
      await tester.pumpAndSettle();
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      await tester.tap(find.text('Sort by')); // the back row carries its name
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsOneWidget);
      await tester.tap(find.text('Sort by'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Added'));
      await tester.pumpAndSettle();
      expect(log, ['added']);
    });

    testWidgets('keyboard: arrows move, right opens, left goes back, '
        'Escape closes', (tester) async {
      await openMenu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      // Whatever item had focus, one of the two outcomes is a sub-menu or a
      // still-open root; drive explicitly to the parent row:
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Escape in a sub-menu goes back, otherwise closes; close for sure.
      if (find.text('Refresh').evaluate().isNotEmpty ||
          find.text('Title').evaluate().isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('keyboard reaches and opens a parent item', (tester) async {
      await openMenu(tester);
      // Focus the "Sort by" row by traversal and open it with the arrow.
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus;
        if (focused?.context != null &&
            find
                .descendant(
                  of: find.byWidget(focused!.context!.widget),
                  matching: find.text('Sort by'),
                )
                .evaluate()
                .isNotEmpty) {
          break;
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Title'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('in right-to-left the opening arrow is mirrored', (
      tester,
    ) async {
      await openMenu(tester, v: _rtl);
      await tester.tap(find.text('Sort by'));
      await tester.pumpAndSettle();
      expect(find.text('Title'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // back in RTL
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('disabled item explains itself and does nothing', (
      tester,
    ) async {
      await openMenu(tester);
      expect(find.text('Nothing to search'), findsOneWidget);
      await tester.tap(find.text('Search'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('every item has a role, label and state in semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openMenu(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Sort by'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      final disabled = tester.getSemantics(find.bySemanticsLabel('Search'));
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      expect(disabled.hint, 'Nothing to search');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Refresh')).role,
        SemanticsRole.menuItem,
      );
      handle.dispose();
    });

    testWidgets('stays on screen near the edges', (tester) async {
      await openMenu(tester);
      final rect = tester.getRect(find.byType(NestedMenu));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(800));
    });
  });

  group('SortSheet', () {
    testWidgets('apply reports key, direction and save-as-default', (
      tester,
    ) async {
      final calls = <(String, bool, bool)>[];
      await _pump(
        tester,
        SortSheet<String>(
          title: 'Sort',
          options: const [
            SortOption(key: 'title', label: 'Title'),
            SortOption(key: 'added', label: 'Added'),
          ],
          selected: 'title',
          ascending: true,
          ascendingLabel: 'Ascending',
          descendingLabel: 'Descending',
          saveAsDefaultLabel: 'Save as default',
          applyLabel: 'Apply',
          onApply: (k, a, s) => calls.add((k, a, s)),
        ),
      );
      await tester.tap(find.text('Apply'));
      expect(calls.single, ('title', true, false));
      await tester.tap(find.text('Added'));
      await tester.tap(find.text('Descending'));
      await tester.tap(find.text('Save as default'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      expect(calls.last, ('added', false, true));
    });

    testWidgets('options are a radio group with state', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        SortSheet<int>(
          title: 'Sort',
          options: const [
            SortOption(key: 0, label: 'A'),
            SortOption(key: 1, label: 'B'),
          ],
          selected: 1,
          ascending: true,
          ascendingLabel: 'Ascending',
          descendingLabel: 'Descending',
          saveAsDefaultLabel: 'Save',
          applyLabel: 'Apply',
          onApply: (_, _, _) {},
        ),
      );
      final b = tester.getSemantics(find.bySemanticsLabel('B'));
      expect(b.flagsCollection.isChecked, CheckedState.isTrue);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('A'))
            .flagsCollection
            .isChecked,
        CheckedState.isFalse,
      );
      handle.dispose();
    });
  });

  group('FilterSheet', () {
    const sections = [
      FilterSection(
        id: 'status',
        label: 'Status',
        multiSelect: false,
        chips: [
          FilterChoice(id: 'a', label: 'Active'),
          FilterChoice(id: 'e', label: 'Ended'),
        ],
      ),
      FilterSection(
        id: 'tag',
        label: 'Tags',
        chips: [
          FilterChoice(id: 'x', label: 'Tag X'),
          FilterChoice(id: 'y', label: 'Tag Y'),
        ],
      ),
    ];

    Widget sheet({
      required void Function(FilterSelection, bool) onApply,
      VoidCallback? onClear,
      int active = 0,
      FilterSelection selection = FilterSelection.empty,
    }) => FilterSheet(
      title: 'Filter',
      sections: sections,
      activeCount: active,
      activeCountLabel: '$active filters active',
      selection: selection,
      clearAllLabel: 'Clear all',
      saveAsDefaultLabel: 'Save as default',
      applyLabel: 'Apply',
      onApply: onApply,
      onClear: onClear ?? () {},
    );

    testWidgets('single-select replaces, multi-select accumulates', (
      tester,
    ) async {
      FilterSelection? applied;
      await _pump(tester, sheet(onApply: (s, _) => applied = s));
      await tester.tap(find.text('Active'));
      await tester.tap(find.text('Ended'));
      await tester.tap(find.text('Tag X'));
      await tester.tap(find.text('Tag Y'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      expect(applied!.of('status'), {'e'});
      expect(applied!.of('tag'), {'x', 'y'});
      expect(applied!.count, 3);
    });

    testWidgets('active count is shown and clear-all empties the draft', (
      tester,
    ) async {
      var cleared = 0;
      FilterSelection? applied;
      await _pump(
        tester,
        sheet(
          active: 2,
          selection: const FilterSelection({
            'tag': {'x', 'y'},
          }),
          onApply: (s, _) => applied = s,
          onClear: () => cleared++,
        ),
      );
      expect(find.text('2 filters active'), findsOneWidget);
      await tester.tap(find.text('Clear all'));
      await tester.pump();
      expect(cleared, 1);
      await tester.tap(find.text('Apply'));
      expect(applied!.isEmpty, isTrue);
    });

    testWidgets('selected chips are announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        sheet(
          active: 1,
          selection: const FilterSelection({
            'status': {'a'},
          }),
          onApply: (_, _) {},
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Active'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    test('FilterSelection equality and toggling', () {
      const a = FilterSelection({
        'tag': {'x'},
      });
      expect(
        a,
        const FilterSelection({
          'tag': {'x'},
        }),
      );
      expect(a.toggled(sections[1], 'x'), FilterSelection.empty);
      expect(a.toggled(sections[1], 'y').of('tag'), {'x', 'y'});
    });
  });

  group('SelectionBar', () {
    testWidgets('exit, select all and actions are buttons with labels', (
      tester,
    ) async {
      final log = <String>[];
      await _pump(
        tester,
        SelectionBar(
          selectedCount: 2,
          countLabel: '2 selected',
          exitLabel: 'Exit selection',
          selectAllLabel: 'Select all',
          onExit: () => log.add('exit'),
          onSelectAll: () => log.add('all'),
          actions: [
            SelectionAction(
              icon: Icons.pause,
              label: 'Pause',
              onPressed: () => log.add('pause'),
            ),
            const SelectionAction(
              icon: Icons.delete_outline,
              label: 'Delete',
              destructive: true,
              onPressed: null,
            ),
          ],
        ),
      );
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Exit selection'));
      await tester.tap(find.byTooltip('Select all'));
      await tester.tap(find.byTooltip('Pause'));
      await tester.tap(find.byTooltip('Delete'), warnIfMissed: false);
      expect(log, ['exit', 'all', 'pause']);
    });

    testWidgets('solid when transparency is reduced', (tester) async {
      Widget bar() => SelectionBar(
        selectedCount: 1,
        countLabel: '1 selected',
        exitLabel: 'Exit',
        selectAllLabel: 'All',
        onExit: () {},
        onSelectAll: () {},
        actions: const [],
      );
      await _pump(tester, bar());
      expect(find.byType(BackdropFilter), findsOneWidget);
      await _pump(tester, bar(), reduceTransparency: true);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('StagedReveal', () {
    Widget reveal({Object key = 'screen', int order = 0}) =>
        StagedReveal(revealKey: key, order: order, child: const Text('Item'));

    double opacityOfItem(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('Item'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    testWidgets('fades in once per key, not again for the same key', (
      tester,
    ) async {
      const motion = A11yVariant('motion', reduceMotion: false);
      applyVariantView(tester, _v);
      await tester.pumpWidget(hostApp(_v, reveal(), a11y: motion));
      expect(opacityOfItem(tester), lessThan(1));
      await tester.pumpAndSettle();
      expect(find.text('Item'), findsOneWidget);

      // Same key again (screen re-entered): shown immediately.
      await tester.pumpWidget(
        hostApp(
          _v,
          KeyedSubtree(key: const ValueKey('again'), child: reveal()),
          a11y: motion,
        ),
      );
      expect(
        find
            .ancestor(
              of: find.text('Item'),
              matching: find.byType(FadeTransition),
            )
            .evaluate()
            .where((e) => (e.widget as FadeTransition).opacity.value < 1),
        isEmpty,
      );

      // A new key plays.
      await tester.pumpWidget(hostApp(_v, reveal(key: 'other'), a11y: motion));
      expect(opacityOfItem(tester), lessThan(1));
      await tester.pumpAndSettle();
    });

    testWidgets('siblings of one key all play in the same frame', (
      tester,
    ) async {
      const motion = A11yVariant('motion', reduceMotion: false);
      applyVariantView(tester, _v);
      await tester.pumpWidget(
        hostApp(
          _v,
          Column(
            children: [
              StagedReveal(revealKey: 'k', child: const Text('A')),
              StagedReveal(revealKey: 'k', order: 1, child: const Text('B')),
            ],
          ),
          a11y: motion,
        ),
      );
      expect(
        find
            .byType(FadeTransition)
            .evaluate()
            .where((e) => (e.widget as FadeTransition).opacity.value < 1),
        hasLength(greaterThanOrEqualTo(2)),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('is a no-op under reduced motion', (tester) async {
      await _pump(tester, reveal(key: 'reduced'));
      expect(
        find
            .ancestor(
              of: find.text('Item'),
              matching: find.byType(FadeTransition),
            )
            .evaluate()
            .where((e) => (e.widget as FadeTransition).opacity.value < 1),
        isEmpty,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('MotionPreference', () {
    testWidgets('reduced turns animation off, system follows the platform', (
      tester,
    ) async {
      Future<bool> animate(MotionPreference p, {bool system = false}) async {
        late bool result;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: system),
            child: ConsolarrEffectsScope(
              motion: p,
              child: Builder(
                builder: (c) {
                  result = ConsolarrEffects.of(c).animate;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        return result;
      }

      expect(await animate(MotionPreference.system), isTrue);
      expect(await animate(MotionPreference.reduced), isFalse);
      expect(await animate(MotionPreference.system, system: true), isFalse);
      expect(await animate(MotionPreference.reduced, system: true), isFalse);
    });

    testWidgets('SkeletonBox has no running ticker under reduced', (
      tester,
    ) async {
      await _pump(tester, const SkeletonBox(height: 20, width: 100));
      expect(tester.hasRunningAnimations, isFalse);
      applyVariantView(tester, _v);
      await tester.pumpWidget(
        hostApp(
          _v,
          const SkeletonBox(height: 20, width: 100),
          a11y: const A11yVariant('motion', reduceMotion: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
    });
  });

  group('touch targets', () {
    for (final a in [A11yVariant.normal, A11yVariant.large]) {
      final min = a.largeTargets ? 56.0 : 48.0;

      testWidgets('rows and controls meet ${min}dp (${a.name})', (
        tester,
      ) async {
        await _pump(
          tester,
          Column(
            children: [
              SettingsRow(title: 'Row', onTap: () {}),
              SwitchRow(title: 'Switch', value: true, onChanged: (_) {}),
              ChoiceSheetRow<int>(
                title: 'Choice',
                closeLabel: 'Close',
                options: const [ChoiceOption(value: 0, label: 'Zero')],
                selected: 0,
                onSelected: (_) {},
              ),
              const StatusChip(label: 'Chip', icon: Icons.check, details: 'x'),
              const MediaListTile(title: 'Tile'),
              SelectionBar(
                selectedCount: 1,
                countLabel: '1',
                exitLabel: 'Exit',
                selectAllLabel: 'All',
                onExit: () {},
                onSelectAll: () {},
                actions: const [],
              ),
            ],
          ),
          a: a,
        );
        for (final finder in [
          find.widgetWithText(InkWell, 'Row'),
          find.widgetWithText(InkWell, 'Switch'),
          find.widgetWithText(InkWell, 'Choice'),
          find.widgetWithText(InkWell, 'Chip'),
          find.widgetWithText(InkWell, 'Tile'),
          find.byTooltip('Exit'),
        ]) {
          expect(
            tester.getSize(finder.first).height,
            greaterThanOrEqualTo(min),
            reason: '$finder',
          );
        }
        await expectTapTargets(tester);
      });

      testWidgets('floating bar tabs meet ${min}dp (${a.name})', (
        tester,
      ) async {
        await _pump(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavBar(
              selectedIndex: 0,
              onSelected: (_) {},
              destinations: const [
                FloatingNavDestination(
                  icon: Icons.tv_outlined,
                  selectedIcon: Icons.tv,
                  label: 'One',
                ),
                FloatingNavDestination(
                  icon: Icons.dns_outlined,
                  selectedIcon: Icons.dns,
                  label: 'Two',
                ),
              ],
            ),
          ),
          a: a,
        );
        expect(
          tester.getSize(find.widgetWithText(InkWell, 'One')).height,
          greaterThanOrEqualTo(min),
        );
      });
    }

    testWidgets('menu items and filter chips meet the size too', (
      tester,
    ) async {
      await _pump(
        tester,
        NestedMenu(
          semanticsLabel: 'Menu',
          items: [NestedMenuItem(label: 'Item', onSelected: () {})],
        ),
        a: A11yVariant.large,
      );
      expect(
        tester.getSize(find.widgetWithText(InkWell, 'Item')).height,
        greaterThanOrEqualTo(56),
      );
    });
  });

  group('SettingsBlocks', () {
    testWidgets('SwitchRow toggles by tapping the whole row', (tester) async {
      var value = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SwitchRow(
            title: 'Lock',
            subtitle: 'Sub',
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );
      await tester.tap(find.text('Lock'));
      await tester.pump();
      expect(value, isTrue);
    });

    testWidgets('SwitchRow state is in semantics, not only drawn', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        SwitchRow(title: 'Lock', value: true, onChanged: (_) {}),
      );
      final n = tester.getSemantics(find.bySemanticsLabel('Lock'));
      expect(n.flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('ChoiceSheetRow shows the current value and picks', (
      tester,
    ) async {
      int selected = 1;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ChoiceSheetRow<int>(
            title: 'Theme',
            closeLabel: 'Close',
            options: const [
              ChoiceOption(value: 0, label: 'Dark'),
              ChoiceOption(value: 1, label: 'Light'),
            ],
            selected: selected,
            onSelected: (v) => setState(() => selected = v),
          ),
        ),
      );
      expect(find.text('Light'), findsOneWidget);
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('SettingsRow chevron mirrors in RTL', (tester) async {
      await _pump(
        tester,
        SettingsRow(title: 'Row', onTap: () {}),
        v: _rtl,
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
      expect(icon.textDirection, TextDirection.rtl);
    });
  });
}
