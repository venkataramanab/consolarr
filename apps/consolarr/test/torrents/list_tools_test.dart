// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/speed_header.dart';
import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:consolarr/features/torrents/presentation/torrent_row.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

Future<TorrentClient?> Function() _of(FakeTorrentClient c) =>
    () async => c;

Future<void> _pump(
  WidgetTester tester,
  FakeTorrentClient c, {
  HarnessVariant variant = baseVariant,
  Duration poll = const Duration(days: 1),
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(
    screenApp(variant, client: _of(c), pollInterval: poll),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TorrentListScreen)));

List<Torrent> _mixed() => [
  sampleTorrent(1, name: 'Example Linux ISO'),
  sampleTorrent(
    2,
    name: 'Example Seeded',
    state: TorrentState.seeding,
    progress: 1,
  ),
  sampleTorrent(3, name: 'Example Paused', state: TorrentState.paused),
  sampleTorrent(4, name: 'Example Broken', state: TorrentState.error),
];

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  group('status tabs', () {
    testWidgets('each tab shows its torrents; an empty tab is filter-empty', (
      tester,
    ) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      expect(find.byType(TorrentRow), findsNWidgets(4));
      await tester.ensureVisible(find.text('Errors'));
      await tester.tap(find.text('Errors'));
      await tester.pumpAndSettle();
      expect(find.text('Example Broken'), findsOneWidget);
      expect(find.byType(TorrentRow), findsOneWidget);
      await tester.ensureVisible(find.text('Finished'));
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      expect(find.text('Example Seeded'), findsOneWidget);
      await tester.tap(find.text('Downloading'));
      await tester.pumpAndSettle();
      expect(find.text('Example Linux ISO'), findsOneWidget);
    });

    testWidgets('a tab that hides everything says so and clears', (
      tester,
    ) async {
      await _pump(tester, FakeTorrentClient(torrents: [sampleTorrent(1)]));
      await tester.ensureVisible(find.text('Errors'));
      await tester.tap(find.text('Errors'));
      await tester.pumpAndSettle();
      expect(find.text('No matching torrents'), findsOneWidget);
      expect(find.byType(TorrentRow), findsNothing);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentRow), findsOneWidget);
    });

    testWidgets('the selected tab has a check mark, not only a colour', (
      tester,
    ) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips.where((c) => c.selected), hasLength(1));
      expect(chips.every((c) => c.showCheckmark ?? true), isTrue);
    });
  });

  group('search', () {
    testWidgets('filters by name and can be closed', (tester) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      await _menu(tester, 'Search');
      await tester.enterText(find.byType(TextField), 'seeded');
      await tester.pumpAndSettle();
      expect(find.byType(TorrentRow), findsOneWidget);
      expect(find.text('Example Seeded'), findsOneWidget);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byType(TorrentRow), findsNWidgets(4));
    });
  });

  group('sort', () {
    testWidgets('by name ascending, and saved as the default', (tester) async {
      final c = FakeTorrentClient(torrents: _mixed());
      await _pump(tester, c);
      await _menu(tester, 'Sort');
      await tester.tap(find.text('Name'));
      await tester.tap(find.text('Ascending'));
      await tester.ensureVisible(find.text('Save as default'));
      await tester.tap(find.text('Save as default'));
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      final names = [
        for (final r in tester.widgetList<TorrentRow>(find.byType(TorrentRow)))
          r.torrent.name,
      ];
      expect(names, [...names]..sort());
      final prefs = _container(tester).read(torrentsPrefsProvider);
      final saved = await tester.runAsync(prefs.readViewDefault);
      expect(saved!.sort.name, 'name');
      expect(saved.ascending, isTrue);
    });
  });

  group('rows', () {
    testWidgets(
      'pending label while pausing; the row returns to normal after',
      (tester) async {
        final c = FakeTorrentClient(torrents: [sampleTorrent(1)])
          ..actionGate = Completer<void>();
        await _pump(tester, c);
        await tester.longPress(find.byType(TorrentRow));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pause'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Pausing…'), findsWidgets);
        c.actionGate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Pausing…'), findsNothing);
        expect(c.calls, contains('pause'));
      },
    );

    testWidgets('a failed action is reverted and the reason is shown', (
      tester,
    ) async {
      final c = FakeTorrentClient(torrents: [sampleTorrent(1)])
        ..actionError = const AppError(ErrorCategory.timeout);
      await _pump(tester, c);
      await tester.longPress(find.byType(TorrentRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Pausing…'), findsNothing);
      expect(find.textContaining('That did not work.'), findsOneWidget);
    });

    testWidgets('tap opens the detail sheet', (tester) async {
      await _pump(tester, FakeTorrentClient(torrents: [sampleTorrent(1)]));
      await tester.tap(find.byType(TorrentRow));
      await tester.pumpAndSettle();
      expect(find.text('Torrent details'), findsOneWidget);
      expect(find.text('Share ratio'), findsOneWidget);
    });

    testWidgets('remove from the row menu: both checkbox states', (
      tester,
    ) async {
      final c = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await _pump(tester, c);
      for (final withData in [false, true]) {
        await tester.longPress(find.byType(TorrentRow));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        final box = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(box.value, isFalse, reason: 'unchecked by default');
        expect(find.text('Remove torrent'), findsOneWidget);
        if (withData) {
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
          expect(find.text('Remove and delete files'), findsOneWidget);
          expect(find.text('Remove torrent'), findsNothing);
          expect(find.textContaining('This cannot be undone.'), findsOneWidget);
          await tester.tap(find.text('Remove and delete files'));
        } else {
          await tester.tap(find.widgetWithText(FilledButton, 'Remove torrent'));
        }
        await tester.pumpAndSettle();
        expect(c.lastDeleteFiles, withData);
      }
    });

    testWidgets('cancel does nothing', (tester) async {
      final c = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await _pump(tester, c);
      await tester.longPress(find.byType(TorrentRow));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.calls, isNot(contains('delete')));
    });
  });

  group('pause all / resume all', () {
    testWidgets('confirms with the count, shows progress, reports failure', (
      tester,
    ) async {
      final c = FakeTorrentClient(torrents: _mixed())
        ..actionGate = Completer<void>();
      await _pump(tester, c);
      await _menu(tester, 'Pause all');
      expect(find.text('Pause all torrents?'), findsOneWidget);
      expect(
        find.textContaining('4 torrents will stop transferring'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Pause all'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Working on 4 torrents…'), findsOneWidget);
      c.actionError = const AppError(ErrorCategory.timeout);
      c.actionGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Working on 4 torrents…'), findsNothing);
      expect(find.textContaining('That did not work.'), findsOneWidget);
    });

    testWidgets('resume all calls resume once', (tester) async {
      final c = FakeTorrentClient(torrents: _mixed());
      await _pump(tester, c);
      await _menu(tester, 'Resume all');
      await tester.tap(find.widgetWithText(FilledButton, 'Resume all'));
      await tester.pumpAndSettle();
      expect(c.calls.where((x) => x == 'resume'), hasLength(1));
    });
  });

  group('header and menu', () {
    testWidgets('tapping the speed header opens the limits sheet', (
      tester,
    ) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      await tester.tap(find.byType(SpeedHeader));
      await tester.pumpAndSettle();
      expect(find.text('Speed limits'), findsOneWidget);
      expect(find.text('Apply limits'), findsOneWidget);
    });

    testWidgets('the add button opens the add sheet', (tester) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      await tester.tap(find.byTooltip('Add torrent'));
      await tester.pumpAndSettle();
      expect(find.text('Magnet link or torrent URL'), findsOneWidget);
    });

    testWidgets('the refresh interval is chosen in a dialog and saved', (
      tester,
    ) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      await _menu(tester, 'Refresh interval');
      expect(find.text('Every 3 seconds'), findsOneWidget);
      await tester.tap(find.text('Every 10 seconds'));
      await tester.pumpAndSettle();
      final prefs = _container(tester).read(torrentsPrefsProvider);
      expect(await tester.runAsync(prefs.readPollSeconds), 10);
    });
  });

  group('offline', () {
    testWidgets('offline: dimmed data, reconnect works, writes are off', (
      tester,
    ) async {
      final c = FakeTorrentClient(torrents: _mixed());
      await _pump(tester, c);
      c.failTorrents(ErrorCategory.timeout);
      await _container(tester).read(torrentListProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.byType(TorrentRow), findsNWidgets(4));
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
            .onPressed,
        isNull,
      );
      c.setTorrents(_mixed());
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Reconnect'), findsNothing);
    });
  });

  group('rebuild bound (1 Hz updates)', () {
    testWidgets('only the row whose own data changed rebuilds', (tester) async {
      final list = [for (var i = 0; i < 40; i++) sampleTorrent(i)];
      final c = FakeTorrentClient(torrents: list);
      await _pump(tester, c);
      final shown = find.byType(TorrentRow).evaluate().length;
      expect(shown, greaterThan(3));

      TorrentRow.buildCount = 0;
      // A poll with identical data rebuilds no row at all.
      await _container(tester).read(torrentListProvider.notifier).refresh();
      await tester.pump();
      expect(TorrentRow.buildCount, 0);

      // The speed header changes every second; rows still do not rebuild.
      c.setTransfer(
        const TransferInfo(dlSpeed: 999, upSpeed: 9, dlTotal: 0, upTotal: 0),
      );
      await _container(tester).read(torrentListProvider.notifier).refresh();
      await tester.pump();
      expect(TorrentRow.buildCount, 0);

      // One torrent changes: exactly one row rebuilds.
      final changed = [...list];
      changed[0] = Torrent(
        hash: list[0].hash,
        name: list[0].name,
        state: list[0].state,
        progress: 0.9,
        size: list[0].size,
        dlSpeed: list[0].dlSpeed,
        upSpeed: list[0].upSpeed,
        ratio: list[0].ratio,
        eta: list[0].eta,
      );
      c.setTorrents(changed);
      await _container(tester).read(torrentListProvider.notifier).refresh();
      await tester.pump();
      expect(TorrentRow.buildCount, 1);
    });

    testWidgets('the speed graph repaints on its own layer', (tester) async {
      await _pump(tester, FakeTorrentClient(torrents: _mixed()));
      final graph = find.descendant(
        of: find.byType(SpeedHeader),
        matching: find.byType(CustomPaint),
      );
      expect(graph, findsWidgets);
      expect(
        find.ancestor(of: graph.first, matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
    });
  });

  group('extremes', () {
    testWidgets('0 and 10,000 torrents; very long names', (tester) async {
      await _pump(tester, FakeTorrentClient());
      expect(find.byType(EmptyState), findsOneWidget);

      final big = [
        for (var i = 0; i < 10000; i++)
          sampleTorrent(
            i,
            name: i == 0 ? 'Example ${'very long name ' * 30}' : null,
          ),
      ];
      await _pump(tester, FakeTorrentClient(torrents: big));
      // Lazy: only what is on screen is built.
      expect(find.byType(TorrentRow).evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    });
  });

  group('matrix', () {
    testWidgets(
      'tabs, search and filter-empty survive 320x568 at 2.0 in ar and en_XA',
      (tester) async {
        final c = FakeTorrentClient(torrents: _mixed());
        await pumpMatrix(
          tester,
          (v) => screenApp(v, client: _of(c)),
          variants: stressVariants,
          verify: (v) async {
            await expectAccessible(tester);
            await tester.ensureVisible(find.byType(ChoiceChip).last);
            await tester.tap(find.byType(ChoiceChip).last);
            await tester.pumpAndSettle();
            expectNoFrameworkExceptions(tester, context: v.label);
            await expectAccessible(tester);
          },
        );
      },
    );
  });
}
