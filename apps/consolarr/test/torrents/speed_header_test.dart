// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/presentation/speed_header.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

List<SpeedSample> _history(int n) => [
  for (var i = 0; i < n; i++)
    SpeedSample(down: (i % 7) * 400000, up: (i % 3) * 90000),
];

Widget _app(
  HarnessVariant v, {
  int? down = 1536000,
  int? up = 51200,
  bool offline = false,
  bool partial = false,
  int history = 30,
  VoidCallback? onTap,
}) => harnessApp(
  v,
  ConsolarrEffectsScope(
    reduceMotion: true,
    child: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SpeedHeader(
          down: down,
          up: up,
          history: _history(history),
          torrentCount: 12,
          offline: offline,
          partial: partial,
          onTap: onTap,
        ),
      ),
    ),
  ),
);

final _stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

void main() {
  final cases = <String, Widget Function(HarnessVariant)>{
    'live': (v) => _app(v),
    'idle': (v) => _app(v, down: 0, up: 0),
    'partial': (v) => _app(v, down: null, up: null, partial: true),
    'offline': (v) => _app(v, offline: true),
    'tappable': (v) => _app(v, onTap: () {}),
    'no history yet': (v) => _app(v, history: 0),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key}: no overflow across the full matrix', (
      tester,
    ) async {
      await pumpMatrix(tester, entry.value);
    });

    testWidgets('${entry.key}: accessible at 320x568, scale 2.0, ar/en_XA', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        entry.value,
        variants: _stress,
        verify: (v) => expectAccessible(tester),
      );
    });
  }

  testWidgets('the graph is decorative: the header reads out the speeds, the '
      'graph adds no node, and it repaints on its own layer', (tester) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(v));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byType(SpeedHeader));
    expect(node.label, contains('12'));
    expect(node.label.toLowerCase(), contains('mb'));

    // The graph is excluded from semantics (the label already says it all).
    expect(
      find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SpeedGraphPainter,
        ),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );

    final graph = find.ancestor(
      of: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SpeedGraphPainter,
      ),
      matching: find.byType(RepaintBoundary),
    );
    expect(graph, findsWidgets);
    handle.dispose();
  });
}
