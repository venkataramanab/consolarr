// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/shared/time/current_day.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

const _pad = EdgeInsets.fromLTRB(16, 60, 16, 88);

// Release dates are date-only (midnight UTC); "today" is the local date.
FakeRadarrApi _api() => FakeRadarrApi()
  ..calendarResult = Result.ok([
    fakeMovie(1, title: 'Day One', digital: DateTime.utc(2026, 5, 1)),
    fakeMovie(2, title: 'Day Two', digital: DateTime.utc(2026, 5, 2)),
    fakeMovie(3, title: 'Day Three', digital: DateTime.utc(2026, 5, 3)),
  ]);

/// The header of the local day [d] (a local midnight, as the page keys it).
Finder _header(DateTime d) => find.byKey(ValueKey('day-$d'));

Finder _today(DateTime d) =>
    find.descendant(of: _header(d), matching: find.textContaining('Today'));

void main() {
  testWidgets('"Today" moves to the next day at local midnight while the page '
      'stays open', (tester) async {
    // The clock is a local time ten seconds before midnight, so the real
    // timer of the day provider has to fire across the boundary.
    var now = DateTime(2026, 5, 1, 23, 59, 50);
    final v = phone.first;
    applyVariantView(tester, v);
    await tester.pumpWidget(
      radarrApp(v, _api(), const CalendarPage(padding: _pad), clock: () => now),
    );
    await tester.pumpAndSettle();

    final one = DateTime(2026, 5, 1);
    final two = DateTime(2026, 5, 2);
    final three = DateTime(2026, 5, 3);
    expect(_today(one), findsOneWidget, reason: 'before midnight: day one');
    expect(_today(two), findsNothing);

    // Cross midnight. Nothing else changes: no refresh, no navigation.
    now = DateTime(2026, 5, 2, 0, 0, 5);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(_today(two), findsOneWidget, reason: 'after midnight: day two');
    expect(_today(one), findsNothing, reason: 'day one is now earlier');
    expect(_today(three), findsNothing);
    expect(
      find.text('Day One').hitTestable(),
      findsNothing,
      reason: 'day one moved above the opening position',
    );
    expect(find.text('Day Two'), findsOneWidget);
  });

  testWidgets('a hidden calendar keeps no midnight timer, and catches up when '
      'it is shown again', (tester) async {
    var now = DateTime(2026, 5, 1, 23, 59, 50);
    final v = phone.first;
    applyVariantView(tester, v);
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      radarrApp(
        v,
        _api(),
        ValueListenableBuilder<bool>(
          valueListenable: shown,
          // TickerMode off is how a tab that is not selected is hidden.
          builder: (_, on, _) => TickerMode(
            enabled: on,
            child: const CalendarPage(padding: _pad),
          ),
        ),
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();
    expect(_today(DateTime(2026, 5, 1)), findsOneWidget);

    shown.value = false;
    await tester.pump();
    now = DateTime(2026, 5, 2, 0, 0, 5);
    await tester.pump(const Duration(minutes: 5));
    // Hidden: the midnight timer is gone, so the day did not move.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarPage, skipOffstage: false)),
    );
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 1));

    shown.value = true;
    await tester.pumpAndSettle();
    expect(_today(DateTime(2026, 5, 2)), findsOneWidget);
    expect(_today(DateTime(2026, 5, 1)), findsNothing);
  });

  testWidgets('a backgrounded app cancels the midnight timer at once, before '
      'any frame runs', (tester) async {
    var now = DateTime(2026, 5, 1, 23, 59, 50);
    final v = phone.first;
    applyVariantView(tester, v);
    await tester.pumpWidget(
      radarrApp(v, _api(), const CalendarPage(padding: _pad), clock: () => now),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarPage)),
    );
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 1));

    // No frame is pumped between the lifecycle change and the clock moving:
    // while paused the engine runs none, so a cancel deferred to a
    // post-frame callback would never happen and the timer would fire.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 5, 2, 0, 0, 5);
    // `pump` elapses the time first (timers fire), then draws one frame.
    await tester.pump(const Duration(minutes: 5));
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(container.read(currentDayProvider), DateTime.utc(2026, 5, 2));
  });
}
