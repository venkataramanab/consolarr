// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeTorrentClient c, {
  Duration poll = const Duration(days: 1),
  HarnessVariant variant = baseVariant,
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(
    sheetApp(
      variant,
      const TorrentDetailSheet(hash: 'hash1'),
      client: c,
      poll: poll,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('data: the overview shows what TOR-08 lists', (tester) async {
    await _pump(tester, FakeTorrentClient());
    expect(find.text('/downloads/example'), findsOneWidget);
    expect(find.text('Share ratio'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Uploaded'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('3 of 10'), findsOneWidget); // seeds
    expect(find.text('2 of 7'), findsOneWidget); // peers
    expect(find.text('Availability'), findsOneWidget);
    expect(find.text('Time left'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('loading shows a skeleton, not stale data', (tester) async {
    final c = FakeTorrentClient();
    applyVariantView(tester, baseVariant);
    final gate = Completer<TorrentClient?>();
    await tester.pumpWidget(
      sheetApp(
        baseVariant,
        const TorrentDetailSheet(hash: 'hash1'),
        client: c,
        clientGate: gate,
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.text('Share ratio'), findsNothing);
    gate.complete(c);
    await tester.pumpAndSettle();
    expect(find.text('Share ratio'), findsOneWidget);
  });

  testWidgets('no seeds hint appears for a downloading torrent without seeds', (
    tester,
  ) async {
    final c = FakeTorrentClient()
      ..detail = TorrentDetail(
        torrent: sampleTorrent(1),
        savePath: '/downloads/example',
        seeds: 0,
        seedsTotal: 0,
        peers: 0,
        peersTotal: 0,
      );
    await _pump(tester, c);
    expect(find.textContaining('No seeds are connected'), findsOneWidget);
  });

  testWidgets('unknown values read Unknown, missing availability is hidden', (
    tester,
  ) async {
    final c = FakeTorrentClient()
      ..detail = TorrentDetail(
        torrent: sampleTorrent(1, state: TorrentState.seeding, progress: 1),
      );
    await _pump(tester, c);
    expect(find.text('Unknown'), findsWidgets);
    expect(find.text('Availability'), findsNothing);
    expect(find.textContaining('No seeds'), findsNothing);
  });

  testWidgets('error: named cause with retry', (tester) async {
    final c = FakeTorrentClient()
      ..detailError = const AppError(ErrorCategory.timeout);
    await _pump(tester, c);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text("Can't load the details"), findsOneWidget);
    c.detailError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Share ratio'), findsOneWidget);
  });

  testWidgets('copy puts the save path on the clipboard, on tap only', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, FakeTorrentClient());
    expect(copied, isNull);
    await tester.tap(find.byTooltip('Copy save path'));
    await tester.pumpAndSettle();
    expect(copied, '/downloads/example');
  });

  testWidgets('refreshes only while open, at the poll interval', (
    tester,
  ) async {
    final c = FakeTorrentClient();
    await _pump(tester, c, poll: const Duration(seconds: 5));
    final first = c.detailCalls;
    await tester.pump(const Duration(seconds: 11));
    expect(c.detailCalls, greaterThan(first));
    await tester.pumpWidget(const SizedBox());
    final closed = c.detailCalls;
    await tester.pump(const Duration(seconds: 30));
    expect(c.detailCalls, closed);
  });

  testWidgets(
    'pause shows in-progress text, then refreshes; failure is explained',
    (tester) async {
      final c = FakeTorrentClient()..actionGate = Completer<void>();
      await _pump(tester, c);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Pausing…'), findsOneWidget);
      c.actionGate!.complete();
      await tester.pumpAndSettle();
      expect(c.calls, contains('pause'));

      c.actionGate = null;
      c.actionError = const AppError(ErrorCategory.timeout);
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(find.textContaining('That did not work.'), findsOneWidget);
    },
  );

  testWidgets('remove: confirm, then the delete flag follows the checkbox', (
    tester,
  ) async {
    final c = FakeTorrentClient();
    await _pump(tester, c);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove torrent?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove torrent'));
    await tester.pumpAndSettle();
    expect(c.lastDeleteFiles, isFalse);
  });

  testWidgets('survives the stress matrix', (tester) async {
    final c = FakeTorrentClient();
    await pumpMatrix(
      tester,
      (v) => sheetApp(v, const TorrentDetailSheet(hash: 'hash1'), client: c),
      variants: stressVariants,
      verify: (v) => expectAccessible(tester),
    );
  });
}
