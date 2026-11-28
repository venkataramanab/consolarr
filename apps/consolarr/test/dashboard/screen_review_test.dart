// SPDX-License-Identifier: GPL-3.0-or-later

// Review fixes of PR #10 for the screen: what the activity tile says, "today"
// after midnight and which cards rebuild on a poll.

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/presentation/activity_card.dart';
import 'package:consolarr/features/dashboard/presentation/media_carousel.dart';
import 'package:core/core.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'screen_support.dart';
import 'support.dart';

final _variant = HarnessVariant(
  size: const Size(412, 915),
  textScale: 1,
  locale: const Locale('en'),
  brightness: Brightness.dark,
);

/// The label without the invisible bidi isolates and word joiners, no-break spaces as spaces.
String _plain(String s) =>
    s.replaceAll(RegExp('[\u2060\u2066-\u2069]'), '').replaceAll('\u00a0', ' ');

void main() {
  final server = FakeServer();
  final sonarr = connection(ServiceKind.sonarr, 's', server);

  Future<void> pump(WidgetTester tester, Env env, CountingSource source) async {
    applyVariantView(tester, _variant);
    await tester.pumpWidget(
      dashboardApp(
        _variant,
        env,
        connections: {ServiceKind.sonarr: sonarr},
        sources: {ServiceKind.sonarr: source.source},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('activity tile', () {
    testWidgets('speaks the service, the counts and the speeds; "Open" is '
        'the hint', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        Env(),
        CountingSource(
          activity: Result.ok(
            summary(active: 2, attention: 1, down: 1536, up: 512),
          ),
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('2 downloading, 1 needs attention')),
      );
      final data = node.getSemanticsData();
      expect(
        _plain(data.label),
        'Sonarr (Server s), 2 downloading, 1 needs attention, '
        'Down 1.5 KB/s, Up 512 B/s',
      );
      expect(data.hint, 'Open');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.bySemanticsLabel(RegExp('^Open ')), findsNothing);
      handle.dispose();
    });

    testWidgets('without speeds the label is the service and the counts', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        Env(),
        CountingSource(activity: Result.ok(summary(active: 3))),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('3 downloading')),
      );
      expect(
        _plain(node.getSemanticsData().label),
        'Sonarr (Server s), 3 downloading',
      );
      handle.dispose();
    });
  });

  group('midnight', () {
    testWidgets('"tomorrow" becomes "today" when the day changes', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 3, 10, 23, 59, 30);
      final env = Env(now: () => now);
      await pump(
        tester,
        env,
        CountingSource(
          upcoming: Result.ok([
            mediaItem(
              'ep:1',
              from: sonarr,
              day: DateTime.utc(2026, 3, 11),
              season: 1,
              episode: 2,
            ),
          ]),
        ),
      );
      expect(find.textContaining('tomorrow'), findsOneWidget);
      expect(find.textContaining('today'), findsNothing);
      now = DateTime.utc(2026, 3, 11, 0, 0, 5);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.textContaining('today'), findsOneWidget);
      expect(find.textContaining('tomorrow'), findsNothing);
    });
  });

  group('rebuilds', () {
    testWidgets('an unchanged poll rebuilds no card; a changed activity '
        'rebuilds only its own', (tester) async {
      final rebuilt = <Type, int>{};
      final source = CountingSource(
        activity: Result.ok(summary(active: 2)),
        upcoming: Result.ok([
          mediaItem('ep:1', from: sonarr, day: DateTime.utc(2026, 3, 11)),
        ]),
        recent: Result.ok([mediaItem('hist:1', from: sonarr, at: fixedNow)]),
      );
      final env = Env();
      await pump(tester, env, source);
      debugOnRebuildDirtyWidget = (element, _) {
        final w = element.widget;
        if (w is ActivityCard || w is UpcomingCard || w is RecentCard) {
          rebuilt[w.runtimeType] = (rebuilt[w.runtimeType] ?? 0) + 1;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      final polls = source.calls[DashboardCard.activity]!;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(source.calls[DashboardCard.activity], polls + 1);
      expect(rebuilt, isEmpty, reason: 'same data: no card rebuilds');

      source.activity = Result.ok(summary(active: 5));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(rebuilt, {ActivityCard: 1});
    });
  });
}
