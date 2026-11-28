// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:core/core.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'screen_support.dart';
import 'support.dart';

class _Locked extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final _locked = NotifierProvider<_Locked, bool>(_Locked.new);

final _variant = HarnessVariant(
  size: const Size(412, 915),
  textScale: 1,
  locale: const Locale('en'),
  brightness: Brightness.dark,
);

void main() {
  final server = FakeServer();
  final sonarr = connection(ServiceKind.sonarr, 's', server);

  late CountingSource source;
  late Env env;
  setUp(() {
    env = Env();
    source = CountingSource(
      upcoming: Result.ok([
        mediaItem('ep:1', from: sonarr, day: DateTime.utc(2026, 3, 11)),
      ]),
    );
  });

  Widget app({Widget Function(Widget screen)? wrapScreen}) {
    return dashboardApp(
      _variant,
      env,
      connections: {ServiceKind.sonarr: sonarr},
      sources: {ServiceKind.sonarr: source.source},
      wrapScreen: wrapScreen,
      appLocked: appLockedProvider.overrideWith((ref) => ref.watch(_locked)),
    );
  }

  int calls(DashboardCard c) => source.calls[c]!;

  Future<void> pumpApp(WidgetTester tester) async {
    applyVariantView(tester, _variant);
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('a visible dashboard polls the activity about every 15 seconds', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(calls(DashboardCard.activity), 1);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(calls(DashboardCard.activity), 2);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(calls(DashboardCard.activity), 3);
    // upcoming and recent were not asked again (not older than 5 minutes)
    expect(calls(DashboardCard.upcoming), 1);
    expect(calls(DashboardCard.recent), 1);
  });

  testWidgets(
    'upcoming and recent refresh on a poll once they are 5 minutes old',
    (tester) async {
      var now = fixedNow;
      env = Env(now: () => now);
      await pumpApp(tester);
      now = fixedNow.add(const Duration(minutes: 5, seconds: 1));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(calls(DashboardCard.upcoming), 2);
      expect(calls(DashboardCard.recent), 2);
    },
  );

  testWidgets('locked: the timer is cancelled, not ticking and skipping; '
      'unlocking polls again', (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    container.read(_locked.notifier).set(true);
    await tester.pump();
    final before = calls(DashboardCard.activity);
    await tester.pump(const Duration(seconds: 15)); // the one tick that notices
    // After that no timer is left: ten minutes later nothing happened and no
    // wake-up is scheduled.
    await tester.pump(const Duration(minutes: 10));
    expect(calls(DashboardCard.activity), before);
    expect(tester.binding.transientCallbackCount, 0);
    container.read(_locked.notifier).set(false);
    await tester.pump();
    await tester.pump();
    expect(calls(DashboardCard.activity), before + 1);
  });

  testWidgets('another tab selected (TickerMode off): hidden, then visible '
      'again polls', (tester) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    applyVariantView(tester, _variant);
    await tester.pumpWidget(
      app(
        wrapScreen: (screen) => ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, on, _) => TickerMode(enabled: on, child: screen),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final before = calls(DashboardCard.activity);
    enabled.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(minutes: 5));
    expect(calls(DashboardCard.activity), before);
    enabled.value = true;
    await tester.pump();
    await tester.pump();
    expect(calls(DashboardCard.activity), before + 1);
  });

  testWidgets(
    'a route pushed over the dashboard pauses it; popping resumes it',
    (tester) async {
      await pumpApp(tester);
      final before = calls(DashboardCard.activity);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('detail')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(minutes: 5));
      expect(calls(DashboardCard.activity), before, reason: 'hidden: no poll');
      navigator.pop();
      await tester.pumpAndSettle();
      expect(calls(DashboardCard.activity), before + 1);
    },
  );

  testWidgets('hidden and resumed: one refresh of every card, no extra polls', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final activity = calls(DashboardCard.activity);
    final upcoming = calls(DashboardCard.upcoming);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(minutes: 3));
    expect(calls(DashboardCard.activity), activity, reason: 'paused: no poll');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(calls(DashboardCard.activity), activity + 1);
    expect(calls(DashboardCard.upcoming), upcoming + 1);
    expect(calls(DashboardCard.recent), upcoming + 1);
  });

  group('announcements', () {
    late List<String> announced;

    setUp(() {
      announced = [];
    });

    void listen(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            if (message is Map && message['type'] == 'announce') {
              final data = message['data'];
              if (data is Map) announced.add('${data['message']}');
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
    }

    testWidgets('poll ticks announce nothing, even when the data changes or '
        'a server fails', (tester) async {
      final handle = tester.ensureSemantics();
      listen(tester);
      await pumpApp(tester);
      source.activity = Result.ok(summary(active: 5));
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      source.activity = const Result.err(AppError(ErrorCategory.timeout));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 60));
        await tester.pump();
      }
      expect(find.byType(Text), findsWidgets);
      expect(announced, isEmpty);
      handle.dispose();
    });

    testWidgets('no live region anywhere on what a poll updates', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      source
        ..activity = const Result.err(AppError(ErrorCategory.serverError))
        ..upcoming = const Result.err(AppError(ErrorCategory.timeout));
      // cached copy under a banner + a failed activity slice
      await env.dashboardCache.write('s', DashboardCard.upcoming, [
        mediaItem('ep:1', from: sonarr, day: DateTime.utc(2026, 3, 11)),
      ], fixedNow);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      final live = [
        for (final n in tester.semantics.simulatedAccessibilityTraversal())
          if (n.flagsCollection.isLiveRegion) n.label,
      ];
      expect(live, isEmpty);
      handle.dispose();
    });

    testWidgets('a pull to refresh announces its result once', (tester) async {
      final handle = tester.ensureSemantics();
      listen(tester);
      await pumpApp(tester);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(announced, [l10n.dashboardRefreshedAnnouncement]);
      expect(calls(DashboardCard.upcoming), 2, reason: 'pull refreshes all');
      handle.dispose();
    });

    testWidgets('a pull with a failing service announces it', (tester) async {
      final handle = tester.ensureSemantics();
      listen(tester);
      await pumpApp(tester);
      source.activity = const Result.err(AppError(ErrorCategory.serverError));
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(announced, [l10n.dashboardRefreshedPartial(1)]);
      handle.dispose();
    });

    testWidgets('pull to refresh keeps the content on screen while it runs', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Example Show'), findsWidgets);
      source.gates[DashboardCard.activity] = Completer();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Example Show'), findsWidgets);
      source.gates[DashboardCard.activity]!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('reduced motion', () {
    testWidgets('skeletons and active rows are static', (tester) async {
      applyVariantView(tester, _variant);
      await tester.pumpWidget(
        dashboardApp(
          _variant,
          env,
          connections: {ServiceKind.sonarr: Completer<Never>() as Object?},
          sources: {ServiceKind.sonarr: source.source},
        ),
      );
      await tester.pump();
      // pumpAndSettle only returns when nothing animates any more
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('with motion on, the skeleton animates', (tester) async {
      applyVariantView(tester, _variant);
      await tester.pumpWidget(
        dashboardApp(
          _variant,
          env,
          connections: {ServiceKind.sonarr: Completer<Never>() as Object?},
          sources: {ServiceKind.sonarr: source.source},
          reduceMotion: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });
  });
}
