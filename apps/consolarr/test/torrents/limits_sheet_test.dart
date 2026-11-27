// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeTorrentClient c, {
  HarnessVariant variant = baseVariant,
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(
    sheetApp(variant, const SpeedLimitsSheet(), client: c),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the current limits and applies new ones in bytes', (
    tester,
  ) async {
    final c = FakeTorrentClient()
      ..limits = const SpeedLimitsState(
        download: 2 * 1024 * 1024,
        upload: 0,
        alternativeActive: false,
      );
    await _pump(tester, c);
    // Download is custom at 2 MB/s, upload is "No limit".
    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    await tester.tap(find.text('Apply limits'));
    await tester.pumpAndSettle();
    expect(c.lastLimits!.download, 2 * 1024 * 1024);
    expect(c.lastLimits!.upload, 0);
    expect(find.text('Limits applied.'), findsOneWidget);
  });

  testWidgets('custom limit with a unit; none sends zero (unlimited)', (
    tester,
  ) async {
    final c = FakeTorrentClient();
    await _pump(tester, c);
    await tester.tap(find.text('Custom limit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('Apply limits'));
    await tester.pumpAndSettle();
    expect(c.lastLimits!.download, 500 * 1024);
    expect(c.lastLimits!.upload, 0);
  });

  testWidgets('an empty or zero custom limit is refused locally', (
    tester,
  ) async {
    final c = FakeTorrentClient();
    await _pump(tester, c);
    await tester.tap(find.text('Custom limit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply limits'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a whole number greater than zero.'),
      findsOneWidget,
    );
    expect(c.lastLimits, isNull);
  });

  testWidgets('applying: the button says so and cannot be pressed twice', (
    tester,
  ) async {
    final c = FakeTorrentClient()..actionGate = Completer<void>();
    await _pump(tester, c);
    await tester.tap(find.text('Apply limits'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Applying…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    c.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(c.calls.where((x) => x == 'setLimits'), hasLength(1));
  });

  testWidgets('apply failure names the reason', (tester) async {
    final c = FakeTorrentClient()
      ..actionError = const AppError(ErrorCategory.timeout);
    await _pump(tester, c);
    await tester.tap(find.text('Apply limits'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not apply the limits.'), findsOneWidget);
  });

  testWidgets('load failure: reason and retry', (tester) async {
    final c = FakeTorrentClient()
      ..limitsError = const AppError(ErrorCategory.authFailed);
    await _pump(tester, c);
    expect(
      find.textContaining('Could not read the current limits.'),
      findsOneWidget,
    );
    c.limitsError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Apply limits'), findsOneWidget);
  });

  group('alternative limits', () {
    testWidgets('shown and working where the client has them', (tester) async {
      final c = FakeTorrentClient();
      await _pump(tester, c);
      expect(find.text('Alternative speed limits'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(c.calls, contains('alt'));
    });

    testWidgets('hidden, with a footnote, where the client has none (Deluge)', (
      tester,
    ) async {
      final c = FakeTorrentClient(kind: ServiceKind.deluge)
        ..capabilities = const TorrentCapabilities(labelModel: LabelModel.label)
        ..limits = const SpeedLimitsState(download: 0, upload: 0);
      await _pump(tester, c);
      expect(find.text('Alternative speed limits'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(
        find.text('This client has no alternative speed limits.'),
        findsOneWidget,
      );
    });

    testWidgets('an older server: disabled with a plain explanation', (
      tester,
    ) async {
      final c = FakeTorrentClient()
        ..actionError = const UnsupportedAction('setAlternativeSpeed');
      await _pump(tester, c);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This client version cannot switch alternative limits from here.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    });
  });

  testWidgets('loading skeleton', (tester) async {
    final c = FakeTorrentClient();
    final gate = Completer<TorrentClient?>();
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(
      sheetApp(
        baseVariant,
        const SpeedLimitsSheet(),
        client: c,
        clientGate: gate,
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBox), findsWidgets);
    gate.complete(c);
    await tester.pumpAndSettle();
    expect(find.text('Apply limits'), findsOneWidget);
  });

  testWidgets('survives the stress matrix', (tester) async {
    final c = FakeTorrentClient();
    await pumpMatrix(
      tester,
      (v) => sheetApp(v, const SpeedLimitsSheet(), client: c),
      variants: stressVariants,
      verify: (v) => expectAccessible(tester),
    );
  });
}
