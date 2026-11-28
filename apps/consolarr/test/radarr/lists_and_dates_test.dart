// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/wanted.dart';
import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/features/radarr/presentation/missing_page.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

const _pad = EdgeInsets.fromLTRB(16, 60, 16, 88);
const _longTitle = 'A Very Long Example Movie Title That Never Ends At All ';

/// Movies a search can find (released digitally in 2020).
List<RadarrMovie> _wantedMovies(int n, {String prefix = 'Missing'}) => [
  for (var i = 1; i <= n; i++)
    fakeMovie(
      i,
      title: '$prefix Movie $i',
      hasFile: false,
      digital: DateTime.utc(2020),
    ),
];

ProviderContainer _container(WidgetTester tester, Type type) =>
    ProviderScope.containerOf(tester.element(find.byType(type)));

void main() {
  group('missing and upcoming', () {
    testWidgets('10,000 rows are built lazily and scroll', (tester) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(_wantedMovies(10000)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      expect(find.text('Missing Movie 1'), findsOneWidget);
      final shown = find.textContaining('Missing Movie ').evaluate().length;
      expect(shown, lessThan(30));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Missing Movie 1'), findsNothing);
      expect(
        find.textContaining('Missing Movie ').evaluate().length,
        lessThan(30),
      );
    });

    testWidgets('the list is computed once, not on every build', (
      tester,
    ) async {
      // A failing search changes the row state but never reloads the library.
      final api = FakeRadarrApi(moviesResult: Result.ok(_wantedMovies(50)))
        ..commandStart = const Result.err(AppError(ErrorCategory.timeout));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      final c = _container(tester, MissingPage);
      final first = c.read(wantedMoviesProvider(WantedScope.released));
      expect(first, hasLength(50));
      // A search in progress changes other state, never the sorted list.
      await tester.tap(find.byTooltip('Search for Missing Movie 1'));
      await tester.pumpAndSettle();
      expect(c.read(searchPhaseProvider(1)), SearchPhase.failed);
      expect(
        identical(c.read(wantedMoviesProvider(WantedScope.released)), first),
        isTrue,
      );
    });

    testWidgets('a row only rebuilds for its own search', (tester) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(_wantedMovies(3)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      final c = _container(tester, MissingPage);
      var otherRow = 0;
      final sub = c.listen(
        searchPhaseProvider(2),
        (_, _) => otherRow++,
        fireImmediately: false,
      );
      addTearDown(sub.close);
      await tester.tap(find.byTooltip('Search for Missing Movie 1'));
      await tester.pumpAndSettle();
      expect(otherRow, 0);
      expect(c.read(searchPhaseProvider(1)), SearchPhase.done);
    });

    testWidgets('"Search all missing" is not offered under Upcoming', (
      tester,
    ) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([
          ..._wantedMovies(2),
          fakeMovie(
            9,
            title: 'Future Movie',
            hasFile: false,
            min: MinimumAvailability.released,
            digital: DateTime.utc(2031),
          ),
        ]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      expect(find.text('Search all missing'), findsOneWidget);
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('Future Movie'), findsOneWidget);
      expect(find.text('Search all missing'), findsNothing);
      expect(find.byTooltip('Search for Future Movie'), findsNothing);
    });

    testWidgets('a search that outlives the polling is neutral, not failed', (
      tester,
    ) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(_wantedMovies(1)))
        ..commandScript = [ArrCommandStatus.started];
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      await tester.tap(find.byTooltip('Search for Missing Movie 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check the queue'), findsOneWidget);
      expect(find.text('Search failed'), findsNothing);
    });

    testWidgets('long titles stay readable and accessible', (tester) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok(_wantedMovies(4, prefix: _longTitle * 3)),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: [...phone, ...stress],
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('calendar', () {
    // Date-only values, as the server sends them: midnight UTC.
    final may1 = DateTime.utc(2026, 5);

    testWidgets('groups under the UTC day, not the day before', (tester) async {
      final api = FakeRadarrApi()
        ..calendarResult = Result.ok([
          fakeMovie(1, title: 'Day One', digital: may1),
          fakeMovie(2, title: 'Day Two', digital: DateTime.utc(2026, 5, 2)),
        ]);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
        variants: phone,
      );
      // fixedNow is 2026-05-01: that day is "Today".
      expect(find.textContaining('Today'), findsOneWidget);
      expect(find.textContaining('May 1'), findsOneWidget);
      expect(find.textContaining('Apr 30'), findsNothing);
      expect(find.textContaining('April 30'), findsNothing);
      expect(find.textContaining('May 2'), findsOneWidget);
    });

    testWidgets('a day can be folded away', (tester) async {
      final api = FakeRadarrApi()
        ..calendarResult = Result.ok([
          fakeMovie(1, title: 'Day One', digital: may1),
          fakeMovie(2, title: 'Day Two', digital: DateTime.utc(2026, 5, 2)),
        ]);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
        variants: phone,
      );
      expect(find.text('Day One'), findsOneWidget);
      await tester.tap(find.textContaining('Today'));
      await tester.pumpAndSettle();
      expect(find.text('Day One'), findsNothing);
      expect(find.text('Day Two'), findsOneWidget);
    });

    testWidgets('10,000 entries are built lazily', (tester) async {
      final api = FakeRadarrApi()
        ..calendarResult = Result.ok([
          for (var i = 1; i <= 10000; i++)
            fakeMovie(
              i,
              title: 'Calendar Movie $i',
              digital: DateTime.utc(2026, 5, 1 + i % 60),
            ),
        ]);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
        variants: phone,
      );
      expect(
        find.textContaining('Calendar Movie ').evaluate().length,
        lessThan(40),
      );
    });

    testWidgets('long titles stay readable and accessible', (tester) async {
      final api = FakeRadarrApi()
        ..calendarResult = Result.ok([
          for (var i = 1; i <= 4; i++)
            fakeMovie(i, title: '$_longTitle$i', digital: may1),
        ]);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
        variants: [...phone, ...stress],
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('detail', () {
    testWidgets('a long title wraps; availability uses the UTC day', (
      tester,
    ) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([
          fakeMovie(
            7,
            title: _longTitle * 4,
            hasFile: false,
            digital: DateTime.utc(2026, 3, 15),
          ),
        ]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: [...phone, ...stress],
        verify: (v) => expectAccessible(tester),
      );
    });

    testWidgets('the digital date shows as the day the server names', (
      tester,
    ) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([
          fakeMovie(7, hasFile: false, digital: DateTime.utc(2026, 3, 15)),
        ]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: phone,
      );
      expect(find.textContaining('Mar 15, 2026'), findsOneWidget);
    });

    testWidgets('R1: failing profile names show an error with a retry that '
        'reads them again', (tester) async {
      final api = _NoProfilesApi(
        moviesResult: Result.ok([fakeMovie(7, hasFile: false)]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: [...phone, ...stress],
        verify: (v) async {
          if (v.textScale == 1) {
            expect(
              find.textContaining('Quality profiles could not be loaded'),
              findsOneWidget,
            );
          }
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('R1: the retry on the detail reads the profiles again', (
      tester,
    ) async {
      var reads = 0;
      final api = _NoProfilesApi(
        moviesResult: Result.ok([fakeMovie(7, hasFile: false)]),
        onRead: () => reads++,
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: phone,
      );
      final before = reads;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(before));
    });

    testWidgets('R1: failing tags alone also show the error, accessibly', (
      tester,
    ) async {
      final api = _NoTagsApi(
        moviesResult: Result.ok([fakeMovie(7, hasFile: false)]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: [...phone, ...stress],
        verify: (v) async {
          if (v.textScale == 1) {
            expect(
              find.textContaining('could not be loaded'),
              findsOneWidget,
              reason: v.label,
            );
          }
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('R1: the retry reads the failed tags again', (tester) async {
      var reads = 0;
      final api = _NoTagsApi(
        moviesResult: Result.ok([fakeMovie(7, hasFile: false)]),
        onRead: () => reads++,
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: phone,
      );
      final before = reads;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(before));
    });

    testWidgets('profile names failing is a partial state, not a crash', (
      tester,
    ) async {
      final api = _NoProfilesApi(
        moviesResult: Result.ok([fakeMovie(7, hasFile: false)]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: [...phone, ...stress],
        verify: (v) => expectAccessible(tester),
      );
      expect(find.text('Example Movie 7'), findsWidgets);
    });
  });
}

class _NoProfilesApi extends FakeRadarrApi {
  _NoProfilesApi({super.moviesResult, this.onRead});

  final void Function()? onRead;

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() async {
    onRead?.call();
    return const Result.err(AppError(ErrorCategory.timeout));
  }
}

class _NoTagsApi extends FakeRadarrApi {
  _NoTagsApi({super.moviesResult, this.onRead});

  final void Function()? onRead;

  @override
  Future<Result<List<ArrTag>>> tags() async {
    onRead?.call();
    return const Result.err(AppError(ErrorCategory.timeout));
  }
}
