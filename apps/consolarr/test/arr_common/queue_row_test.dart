// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/queue_row_builder.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../sonarr/fakes.dart';

Widget _app(HarnessVariant v, List<Widget> rows) => harnessApp(
  v,
  ConsolarrEffectsScope(
    reduceMotion: true,
    child: Scaffold(
      body: ListView(padding: const EdgeInsets.all(16), children: rows),
    ),
  ),
);

final _stress = harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  locales: const [Locale('en'), Locale('ar'), Locale('en', 'XA')],
);

void main() {
  testWidgets('every state shows icon and text without overflow (matrix)', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => _app(v, [
        for (final s in ArrQueueState.values)
          ArrQueueItemRow(
            item: fakeQueueItem(1, state: s),
            mediaLabel: 'Example Show ${s.name}',
            extraDetails: const ['S1E2 · Example Episode'],
            onRemove: () {},
          ),
      ]),
      variants: _stress,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('long titles and messages do not overflow', (tester) async {
    await pumpMatrix(
      tester,
      (v) => _app(v, [
        ArrQueueItemRow(
          item: fakeQueueItem(
            1,
            messages: [
              ArrStatusMessage(
                title: 'Title ${'long ' * 30}',
                messages: ['Message ${'long ' * 40}'],
              ),
            ],
          ),
          mediaLabel: 'Example Show ${'Very Long Title ' * 12}',
          onRemove: () {},
        ),
      ]),
      variants: harnessMatrix(
        sizes: const [Size(320, 568)],
        textScales: const [2],
        locales: const [Locale('ar'), Locale('en', 'XA')],
      ),
    );
  });

  testWidgets('semantics state name, percentage and details', (tester) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(v, [
        ArrQueueItemRow(
          item: fakeQueueItem(1, progress: 0.5),
          mediaLabel: 'Example Show 1',
          onRemove: () {},
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('Example Show 1, Downloading, 50%')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('warnings expand to plain text', (tester) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(
      _app(v, [
        ArrQueueItemRow(
          item: fakeQueueItem(
            1,
            state: ArrQueueState.warning,
            messages: const [
              ArrStatusMessage(
                title: 'Example.Show.S01E01',
                messages: ['<b>Not an upgrade</b>'],
              ),
            ],
          ),
          mediaLabel: 'Example Show 1',
          onRemove: () {},
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 message'), findsOneWidget);
    expect(find.text('<b>Not an upgrade</b>'), findsNothing);
    await tester.tap(find.text('1 message'));
    await tester.pumpAndSettle();
    // Markup is shown literally, as text.
    expect(find.textContaining('<b>Not an upgrade</b>'), findsOneWidget);
  });

  testWidgets('remove is disabled and explained when no handler', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(
      _app(v, [
        ArrQueueItemRow(
          item: fakeQueueItem(1),
          mediaLabel: 'Example Show 1',
          removeDisabledReason: 'Needs a connection',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'Needs a connection');
  });
}
