// SPDX-License-Identifier: GPL-3.0-or-later

// The floating bar paints last but must be read first. The scaffold is shared
// by every tab screen, so this checks the traversal order of another screen
// (Settings) and of the scaffold alone, not only of the dashboard.

import 'package:consolarr/features/settings/presentation/settings_screen.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../settings/screens_support.dart';

const _tall = HarnessVariant(
  size: Size(360, 2600),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

List<String> _traversal(WidgetTester tester) => [
  for (final n in tester.semantics.simulatedAccessibilityTraversal())
    if (n.label.isNotEmpty) n.label,
];

void main() {
  testWidgets('Settings: the bar title is read first, then the groups in '
      'visual order', (tester) async {
    final handle = tester.ensureSemantics();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final h = ScreenHarness();
    applyVariantView(tester, _tall);
    await tester.pumpWidget(
      h.screen(_tall, const Scaffold(body: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    final order = _traversal(tester);
    expect(order.first, l10n.settingsTitle, reason: 'the bar is read first');
    int at(String label) =>
        order.indexWhere((l) => l.contains(label), 1); // after the title
    final groups = [
      l10n.settingsSectionServers,
      l10n.settingsSectionDisplay,
      l10n.settingsSectionSecurity,
      l10n.settingsSectionPrivacy,
    ];
    final positions = [for (final g in groups) at(g)];
    expect(positions, everyElement(greaterThan(0)), reason: '$order');
    expect(
      positions,
      orderedEquals([...positions]..sort()),
      reason: 'the body follows top to bottom',
    );
    handle.dispose();
  });

  testWidgets(
    'the scaffold alone: title first, then the body; the action is reachable',
    (tester) async {
      final handle = tester.ensureSemantics();
      final h = ScreenHarness();
      applyVariantView(tester, _tall);
      await tester.pumpWidget(
        h.screen(
          _tall,
          Scaffold(
            body: FloatingTopBarScaffold(
              title: 'Bar title',
              actions: [
                IconButton(
                  tooltip: 'Bar action',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {},
                ),
              ],
              bodyBuilder: (context, padding) => ListView(
                padding: padding,
                children: const [Text('First line'), Text('Second line')],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_traversal(tester), ['Bar title', 'First line', 'Second line']);
      // The icon button names itself with its tooltip.
      expect([
        for (final n in tester.semantics.simulatedAccessibilityTraversal())
          n.tooltip,
      ], contains('Bar action'));
      final headers = [
        for (final n in tester.semantics.simulatedAccessibilityTraversal())
          if (n.flagsCollection.isHeader) n.label,
      ];
      expect(headers, ['Bar title']);
      handle.dispose();
    },
  );
  testWidgets('the bar is read first even when it is taller than half the '
      'screen', (tester) async {
    // The tests above would pass without the scaffold's sort keys: a bar of
    // normal height has its centre above the body's, so geometry alone reads
    // it first. With a tall banner on a short screen (large text, landscape)
    // the bar's centre falls below the body's, geometry reads the body first,
    // and only the sort keys (bar 0, body 1) keep the bar first.
    const short = HarnessVariant(
      size: Size(360, 300),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    final handle = tester.ensureSemantics();
    final h = ScreenHarness();
    applyVariantView(tester, short);
    await tester.pumpWidget(
      h.screen(
        short,
        Scaffold(
          body: FloatingTopBarScaffold(
            title: 'Bar title',
            banner: const SizedBox(height: 400, child: Text('Banner line')),
            bodyBuilder: (context, padding) => ListView(
              padding: padding,
              children: const [Text('First line'), Text('Second line')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The premise: the bar's box is centred below the body's (half the view).
    expect(
      tester.getCenter(find.text('Banner line')).dy,
      greaterThan(short.size.height / 2),
      reason: 'geometry alone would put the body before the bar',
    );
    expect(_traversal(tester), [
      'Bar title',
      'Banner line',
      'First line',
      'Second line',
    ]);
    handle.dispose();
  });
}
