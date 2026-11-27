// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

Future<TorrentClient?> Function() clientOf(FakeTorrentClient c) =>
    () async => c;

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TorrentListScreen)));

void main() {
  group(
    'states survive the matrix (overflow, a11y at 2.0 in ar and en_XA)',
    () {
      testWidgets('loading skeleton', (tester) async {
        await expectStateSurvivesMatrix(
          tester,
          () => Future<TorrentClient?>.delayed(const Duration(days: 365)),
        );
        expect(find.byType(SkeletonBox), findsWidgets);
        // Drain the long-lived timer so the test ends cleanly.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(days: 366));
      });

      testWidgets('data: every torrent state', (tester) async {
        await expectStateSurvivesMatrix(
          tester,
          clientOf(FakeTorrentClient(torrents: allStates())),
        );
        expect(find.byType(ProgressFillRow), findsWidgets);
      });

      testWidgets('empty', (tester) async {
        await expectStateSurvivesMatrix(tester, clientOf(FakeTorrentClient()));
        expect(find.byType(EmptyState), findsOneWidget);
      });

      testWidgets('no server configured (with and without action)', (
        tester,
      ) async {
        await expectStateSurvivesMatrix(tester, () async => null);
        expect(find.byType(EmptyState), findsOneWidget);
      });

      testWidgets('partial: transfer statistics missing', (tester) async {
        await expectStateSurvivesMatrix(
          tester,
          clientOf(
            FakeTorrentClient(torrents: [sampleTorrent(1)], transfer: null),
          ),
        );
        expect(find.byType(ProgressFillRow), findsOneWidget);
      });

      testWidgets('idle: zero speeds', (tester) async {
        await expectStateSurvivesMatrix(
          tester,
          clientOf(
            FakeTorrentClient(
              torrents: [sampleTorrent(1, state: TorrentState.paused)],
              transfer: const TransferInfo(
                dlSpeed: 0,
                upSpeed: 0,
                dlTotal: 0,
                upTotal: 0,
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          screenApp(
            baseVariant,
            client: clientOf(
              FakeTorrentClient(
                torrents: [sampleTorrent(1, state: TorrentState.paused)],
                transfer: const TransferInfo(
                  dlSpeed: 0,
                  upSpeed: 0,
                  dlTotal: 0,
                  upTotal: 0,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Idle'), findsNWidgets(2));
      });

      testWidgets('error: every category', (tester) async {
        for (final category in ErrorCategory.values) {
          final client = FakeTorrentClient()..failTorrents(category);
          await expectStateSurvivesMatrix(tester, clientOf(client));
          expect(
            find.byType(ErrorState),
            findsOneWidget,
            reason: category.code,
          );
        }
      });

      testWidgets('offline with the last data (banner, opaque text)', (
        tester,
      ) async {
        await expectStateSurvivesMatrix(
          tester,
          () async =>
              FakeTorrentClient(torrents: allStates())..failFromCall = 2,
          verify: (v) async {
            await containerOf(tester)
                .read(torrentListProvider.notifier)
                .refresh();
            await tester.pumpAndSettle();
            expectNoFrameworkExceptions(tester, context: 'offline ${v.label}');
            expect(find.byType(OfflineBanner), findsOneWidget);
            // On small, large-text screens the banner and header fill the
            // viewport; scroll so the dimmed rows are built.
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ProgressFillRow), findsWidgets, reason: v.label);
            if (v.textScale == 2) await expectAccessible(tester);
          },
        );
      });

      testWidgets('extremes: very long names', (tester) async {
        final long = 'Example Torrent ${'with a very long name ' * 20}';
        await expectStateSurvivesMatrix(
          tester,
          clientOf(
            FakeTorrentClient(
              torrents: [
                for (var i = 0; i < 3; i++) sampleTorrent(i, name: '$long$i'),
                sampleTorrent(9, name: 'x' * 400),
              ],
            ),
          ),
        );
      });

      testWidgets('extremes: 0 torrents is the empty state', (tester) async {
        await tester.pumpWidget(
          screenApp(
            baseVariant,
            client: clientOf(FakeTorrentClient(torrents: const [])),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProgressFillRow), findsNothing);
        expect(find.byType(EmptyState), findsOneWidget);
      });

      testWidgets('extremes: 10,000 torrents build lazily', (tester) async {
        final many = [for (var i = 0; i < 10000; i++) sampleTorrent(i)];
        await pumpMatrix(
          tester,
          (v) =>
              screenApp(v, client: clientOf(FakeTorrentClient(torrents: many))),
          variants: [
            const HarnessVariant(
              size: Size(320, 568),
              textScale: 2,
              locale: Locale('ar'),
              brightness: Brightness.dark,
            ),
            baseVariant,
          ],
        );
        // Only the visible rows exist.
        expect(find.byType(ProgressFillRow).evaluate().length, lessThan(40));
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -20000),
        );
        await tester.pumpAndSettle();
        expectNoFrameworkExceptions(tester);
        expect(find.byType(ProgressFillRow).evaluate().length, lessThan(40));
      });
    },
  );

  group('behaviour', () {
    testWidgets('the retry button on an error state reloads', (tester) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)])
        ..failTorrents(ErrorCategory.timeout);
      await tester.pumpWidget(screenApp(baseVariant, client: clientOf(client)));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      client.setTorrents([sampleTorrent(1)]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byType(ProgressFillRow), findsOneWidget);
    });

    testWidgets('the offline banner reconnects', (tester) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)])
        ..failFromCall = 2;
      await tester.pumpWidget(screenApp(baseVariant, client: clientOf(client)));
      await tester.pumpAndSettle();
      await containerOf(tester).read(torrentListProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.byType(OfflineBanner), findsOneWidget);
      client.failFromCall = null;
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(find.byType(OfflineBanner), findsNothing);
    });

    testWidgets('the no-server action calls onAddServer', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: () async => null,
          onAddServer: () => tapped++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a server'));
      expect(tapped, 1);
    });

    testWidgets('the speed header tap hook is wired', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(FakeTorrentClient(torrents: [sampleTorrent(1)])),
          onSpeedHeaderTap: () => tapped++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      expect(tapped, 1);
    });

    testWidgets('pull to refresh keeps the content and reloads', (
      tester,
    ) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(screenApp(baseVariant, client: clientOf(client)));
      await tester.pumpAndSettle();
      final before = client.listCalls;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      expect(find.byType(ProgressFillRow), findsOneWidget);
      await tester.pumpAndSettle();
      expect(client.listCalls, greaterThan(before));
      expect(find.byType(ProgressFillRow), findsOneWidget);
    });

    testWidgets('a progress row announces state and percentage in words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(
            FakeTorrentClient(
              torrents: [sampleTorrent(1, name: 'Example Torrent 1')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.getSemantics(find.byType(ProgressFillRow)).label;
      expect(label, contains('Example Torrent 1'));
      expect(label, contains('Downloading'));
      expect(label, contains('42%'));
      handle.dispose();
    });

    testWidgets('every state shows an icon and its text', (tester) async {
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(FakeTorrentClient(torrents: allStates())),
        ),
      );
      await tester.pumpAndSettle();
      for (final row in tester.widgetList<ProgressFillRow>(
        find.byType(ProgressFillRow),
      )) {
        expect(row.stateLabel, isNotEmpty);
        expect(row.stateIcon, isA<IconData>());
        expect(row.semanticsLabel, contains(row.stateLabel));
        expect(row.semanticsLabel, contains(row.progressLabel));
      }
    });

    testWidgets('active rows animate only without reduced motion', (
      tester,
    ) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(baseVariant, client: clientOf(client), reduceMotion: false),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        screenApp(baseVariant, client: clientOf(client), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('polling lifecycle', () {
    const interval = Duration(seconds: 3);

    testWidgets('polls on the interval while visible and resumed', (
      tester,
    ) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(client),
          pollInterval: interval,
        ),
      );
      await tester.pumpAndSettle();
      final first = client.listCalls;
      await tester.pump(interval);
      await tester.pumpAndSettle();
      expect(client.listCalls, first + 1);
      await tester.pump(interval);
      await tester.pumpAndSettle();
      expect(client.listCalls, first + 2);
    });

    testWidgets('pauses in the background and refreshes on resume', (
      tester,
    ) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(client),
          pollInterval: interval,
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = client.listCalls;
      await tester.pump(interval * 3);
      expect(client.listCalls, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.listCalls, before + 1);
    });

    testWidgets('does not poll while the tab is hidden', (tester) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(client),
          pollInterval: interval,
          tickerEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      final before = client.listCalls;
      await tester.pump(interval * 3);
      expect(client.listCalls, before);
    });

    testWidgets('stops polling when the screen is disposed', (tester) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(client),
          pollInterval: interval,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      final before = client.listCalls;
      await tester.pump(interval * 5);
      expect(client.listCalls, before);
    });

    testWidgets('no polling while the app lock is closed; resumes on unlock', (
      tester,
    ) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(client),
          pollInterval: interval,
        ),
      );
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      container.read(testLockedProvider.notifier).set(true);
      await tester.pump();
      final locked = client.listCalls;
      await tester.pump(interval * 5);
      expect(client.listCalls, locked, reason: 'locked: no poll');
      container.read(testLockedProvider.notifier).set(false);
      await tester.pumpAndSettle();
      expect(client.listCalls, locked + 1, reason: 'unlock polls once');
    });

    testWidgets('resume while the tab is hidden does not poll', (tester) async {
      final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
      await tester.pumpWidget(
        screenApp(
          baseVariant,
          client: clientOf(client),
          pollInterval: interval,
          tickerEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = client.listCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.listCalls, before);
    });
  });
}
