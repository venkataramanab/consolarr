// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

const _pad = EdgeInsets.fromLTRB(16, 60, 16, 88);

// fixedNow is 2026-05-01 12:00Z. Release dates are date-only (midnight UTC).
FakeRadarrApi _api() => FakeRadarrApi()
  ..calendarResult = Result.ok([
    fakeMovie(1, title: 'Past Far', digital: DateTime.utc(2026, 4, 18)),
    fakeMovie(2, title: 'Past Near', digital: DateTime.utc(2026, 4, 29)),
    fakeMovie(3, title: 'Opening Day', digital: DateTime.utc(2026, 5, 1)),
    fakeMovie(4, title: 'Soon', digital: DateTime.utc(2026, 5, 4)),
    fakeMovie(5, title: 'Later', digital: DateTime.utc(2026, 6, 20)),
  ]);

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('opens on today with upcoming days first; earlier days sit '
      'above', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const CalendarPage(padding: _pad)),
      variants: phone,
    );
    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.text('Opening Day'), findsOneWidget);
    expect(find.text('Soon'), findsOneWidget);
    // Upcoming reads top to bottom, soonest first.
    expect(_top(tester, 'Opening Day'), lessThan(_top(tester, 'Soon')));
    // The earlier days are not on screen at the start...
    expect(find.text('Past Near').hitTestable(), findsNothing);
    expect(find.text('Past Far').hitTestable(), findsNothing);
  });

  testWidgets('the past 14 days stay reachable by scrolling up, oldest at '
      'the top', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const CalendarPage(padding: _pad)),
      variants: phone,
      verify: (_) async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(find.text('Past Near').hitTestable(), findsOneWidget);
        expect(find.text('Past Near'), findsOneWidget);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
        await tester.pumpAndSettle();
        expect(find.text('Past Far').hitTestable(), findsOneWidget);
        // Chronological from top to bottom, ending right above today.
        expect(_top(tester, 'Past Far'), lessThan(_top(tester, 'Past Near')));
      },
    );
  });

  testWidgets('without earlier days it opens exactly as before', (
    tester,
  ) async {
    final api = FakeRadarrApi()
      ..calendarResult = Result.ok([
        fakeMovie(3, title: 'Opening Day', digital: DateTime.utc(2026, 5, 1)),
      ]);
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
      variants: phone,
    );
    expect(find.text('Opening Day').hitTestable(), findsOneWidget);
    // Nothing above the opening position: pulling down does not scroll.
    final before = _top(tester, 'Opening Day');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
    await tester.pump();
    expect(_top(tester, 'Opening Day'), greaterThanOrEqualTo(before));
  });

  testWidgets('a folded earlier day stays folded', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, _api(), const CalendarPage(padding: _pad)),
      variants: phone,
      verify: (_) async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(find.text('Past Near'), findsOneWidget);
        await tester.tap(find.textContaining('Apr 29'));
        await tester.pumpAndSettle();
        expect(find.text('Past Near'), findsNothing);
      },
    );
  });

  testWidgets('only earlier days: says nothing is upcoming and the earlier '
      'days stay reachable by scrolling up', (tester) async {
    final api = FakeRadarrApi()
      ..calendarResult = Result.ok([
        fakeMovie(1, title: 'Past Far', digital: DateTime.utc(2026, 4, 18)),
        fakeMovie(2, title: 'Past Near', digital: DateTime.utc(2026, 4, 29)),
      ]);
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
      variants: phone,
      verify: (_) async {
        // Not a blank screen: the opening view says why.
        expect(
          find.text('No upcoming releases. Scroll up for earlier ones.'),
          findsOneWidget,
        );
        expect(find.text('Past Near').hitTestable(), findsNothing);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(find.text('Past Near').hitTestable(), findsOneWidget);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
        await tester.pumpAndSettle();
        expect(find.text('Past Far').hitTestable(), findsOneWidget);
      },
    );
  });

  testWidgets('nothing in the window at all still shows the empty state, not '
      'the upcoming row', (tester) async {
    final api = FakeRadarrApi()..calendarResult = Result.ok(const []);
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
      variants: phone,
    );
    expect(
      find.text('No upcoming releases. Scroll up for earlier ones.'),
      findsNothing,
    );
    expect(find.textContaining('release date in this range'), findsOneWidget);
  });
}
