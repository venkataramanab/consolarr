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

void main() {
  Future<void> openMenu(WidgetTester tester) async {
    await _pump(
      tester,
      Align(
        alignment: AlignmentDirectional.topEnd,
        child: Builder(
          builder: (context) => IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onPressed: () => showNestedMenu(context, anchorRectOf(context), [
              NestedMenuItem(label: 'Refresh', onSelected: () {}),
              NestedMenuItem(
                label: 'Sort by',
                children: [NestedMenuItem(label: 'Title')],
              ),
            ], 'More actions'),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('system back steps out of a sub-menu, then closes', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.text('Sort by'));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Title'), findsNothing);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsNothing);
  });

  testWidgets('opening a sub-menu announces its name', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMenu(tester);
    await tester.tap(find.text('Sort by'));
    await tester.pump();
    final live = tester
        .getSemantics(find.byKey(const ValueKey('nested-menu-announcer')))
        .label;
    expect(live, contains('Sort by'));
    semantics.dispose();
  });

  testWidgets('opens above the nav bar on the root navigator', (tester) async {
    applyVariantView(tester, _v);
    await tester.pumpWidget(
      harnessApp(
        _v,
        Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Builder(
                builder: (context) => TextButton(
                  onPressed: () => showNestedMenu(
                    context,
                    anchorRectOf(context),
                    [NestedMenuItem(label: 'Refresh', onSelected: () {})],
                    'More actions',
                  ),
                  child: const Text('open'),
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
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar')).hitTestable(), findsNothing);
  });
}
