// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/home/sonarr_home_screen.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

List<SonarrTab> _tabs() => [
  for (final (id, name) in [
    ('one', 'First'),
    ('two', 'Second'),
    ('three', 'Third'),
  ])
    SonarrTab(
      id: id,
      icon: Icons.circle_outlined,
      label: (_) => name,
      body: (context, padding) => Center(child: Text('body $id')),
      actions: id == 'two'
          ? (context) => [
              IconButton(
                tooltip: 'Second action',
                icon: const Icon(Icons.star),
                onPressed: () {},
              ),
            ]
          : null,
    ),
];

Widget _app(HarnessVariant v) => ProviderScope(
  child: harnessApp(
    v,
    ConsolarrEffectsScope(
      reduceMotion: true,
      child: Scaffold(body: SonarrHomeScreen(tabs: _tabs())),
    ),
  ),
);

const _phone = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

void main() {
  testWidgets('shows the first tab and the strip with every tab', (
    tester,
  ) async {
    applyVariantView(tester, _phone);
    await tester.pumpWidget(_app(_phone));
    await tester.pumpAndSettle();
    expect(find.text('body one'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    expect(find.byTooltip('Second action'), findsNothing);
  });

  testWidgets('tapping a tab opens it and swaps the top bar actions', (
    tester,
  ) async {
    applyVariantView(tester, _phone);
    await tester.pumpWidget(_app(_phone));
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(find.text('body two'), findsOneWidget);
    expect(find.byTooltip('Second action'), findsOneWidget);
  });

  testWidgets('swiping moves between tabs and the strip follows', (
    tester,
  ) async {
    applyVariantView(tester, _phone);
    await tester.pumpWidget(_app(_phone));
    await tester.drag(find.text('body one'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('body two'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('sonarr-tab-two')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets(
    'right-to-left: the first tab is on the right and swipe reverses',
    (tester) async {
      const rtl = HarnessVariant(
        size: Size(360, 800),
        textScale: 1,
        locale: Locale('ar'),
        brightness: Brightness.dark,
      );
      applyVariantView(tester, rtl);
      await tester.pumpWidget(_app(rtl));
      await tester.pumpAndSettle();
      final first = tester.getCenter(
        find.byKey(const ValueKey('sonarr-tab-one')),
      );
      final second = tester.getCenter(
        find.byKey(const ValueKey('sonarr-tab-two')),
      );
      expect(first.dx, greaterThan(second.dx));
      await tester.drag(find.text('body one'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.text('body two'), findsOneWidget);
    },
  );

  testWidgets('accessible and without overflow at the stress sizes', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      _app,
      variants: harnessMatrix(
        sizes: const [Size(320, 568)],
        textScales: const [2],
        locales: const [Locale('ar'), Locale('en', 'XA')],
      ),
      verify: (v) => expectAccessible(tester),
    );
  });
}
