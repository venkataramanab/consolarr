// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:consolarr/features/torrents/presentation/speed_header.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
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

void main() {
  final cases = <String, Widget Function(HarnessVariant)>{
    'live': (v) => _app(v),
    'idle': (v) => _app(v, down: 0, up: 0),
    'partial': (v) => _app(v, down: null, up: null, partial: true),
    'offline': (v) => _app(v, offline: true),
    'tappable': (v) => _app(v, onTap: () {}),
    'no history yet': (v) => _app(v, history: 0),
  };

  // T6: at 2.0 text scale a speed such as "512 B/s" must never break between
  // the "/" and the unit ("512 B/" then "s").
  for (final locale in const [Locale('en'), Locale('ar'), Locale('en', 'XA')]) {
    testWidgets('T6: the header shows the unbreakable speed in $locale', (
      tester,
    ) async {
      final v = HarnessVariant(
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
        brightness: Brightness.dark,
      );
      applyVariantView(tester, v);
      await tester.pumpWidget(_app(v, down: 512, up: 12 * 1024 * 1024));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final bytes in [512, 12 * 1024 * 1024]) {
        expect(find.text(formatSpeedDisplay(l10n, bytes)), findsOneWidget);
      }
      // The spoken label keeps the plain text (no joiners are read out).
      expect(
        tester.getSemantics(find.byType(SpeedHeader)).label,
        isNot(contains('\u2060')),
      );
    });
  }

  test('T6: a narrow line breaks before the speed, never inside its unit', () {
    TextPainter painter(String text, double width) => TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

    const plain = '512 B/s';
    final display = keepSpeedUnitTogether(plain);
    // Just wide enough for "512 B/" but not for the "s".
    final width =
        (TextPainter(
          text: const TextSpan(text: '512 B/', style: TextStyle(fontSize: 20)),
          textDirection: TextDirection.ltr,
        )..layout()).width +
        1;

    final before = painter(plain, width);
    // The bug: the plain text breaks right after the slash.
    expect(before.getLineBoundary(const TextPosition(offset: 0)).end, 6);

    final after = painter(display, width);
    final firstLine = after.getLineBoundary(const TextPosition(offset: 0));
    // The first line stops before the unit; "B", "/" and "s" stay together.
    expect(firstLine.end, lessThanOrEqualTo(4));
    expect(after.computeLineMetrics().length, 2);
  });

  test('T6: the joiners are the only change', () {
    expect(keepSpeedUnitTogether('1.5 KB/s'), '1.5 KB\u2060/\u2060s');
    expect(
      keepSpeedUnitTogether('1.5 KB/s').replaceAll('\u2060', ''),
      '1.5 KB/s',
    );
    expect(keepSpeedUnitTogether('no slash'), 'no slash');
  });

  for (final entry in cases.entries) {
    testWidgets('${entry.key}: no overflow across the full matrix', (
      tester,
    ) async {
      await pumpMatrix(tester, entry.value);
    });

    testWidgets('${entry.key}: accessible across the full matrix', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        entry.value,
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

  for (final (name, v) in [
    (
      'en_dark_360x800',
      const HarnessVariant(
        size: Size(360, 800),
        textScale: 1,
        locale: Locale('en'),
        brightness: Brightness.dark,
      ),
    ),
    (
      'ar_light_320x568_x2',
      const HarnessVariant(
        size: Size(320, 568),
        textScale: 2,
        locale: Locale('ar'),
        brightness: Brightness.light,
      ),
    ),
  ]) {
    testWidgets('golden: speed header $name', (tester) async {
      applyVariantView(tester, v);
      await tester.pumpWidget(_app(v, down: 512, up: 12 * 1024 * 1024));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/torrents_speed_header_$name.png'),
      );
    });
  }
}
