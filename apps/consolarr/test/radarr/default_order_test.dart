// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/domain/wanted.dart';
import 'package:consolarr/features/radarr/data/radarr_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<int> _ids(Iterable<RadarrMovie> m) => [for (final x in m) x.id];

void main() {
  group('library default', () {
    test('a new query is date added, newest first', () {
      const q = MovieQuery();
      expect(q.sort, MovieSortKey.added);
      expect(q.ascending, isFalse);
    });

    test('the newest movie comes first, undated ones last, ties by title', () {
      final sameDay = DateTime.utc(2025, 6, 1);
      final movies = [
        fakeMovie(1, title: 'Old'), // added 2024-01-02
        fakeMovie(2, title: 'Bravo'),
        fakeMovie(3, title: 'Alpha'),
        fakeMovie(4, title: 'Newest'),
      ];
      final withDates = [
        for (final m in movies)
          switch (m.id) {
            1 => m,
            2 || 3 => _withAdded(m, sameDay),
            _ => _withAdded(m, DateTime.utc(2026, 1, 1)),
          },
        _withAdded(fakeMovie(5, title: 'Undated'), null),
      ];
      expect(_ids(applyQuery(withDates, const MovieQuery())), [4, 3, 2, 1, 5]);
    });

    test('a saved default beats the built-in one', () async {
      final prefs = MemoryPrefs();
      prefs.values[RadarrPrefKeys.librarySort('srv1')] = jsonEncode({
        'key': 'title',
        'asc': true,
      });
      final container = ProviderContainer(
        overrides: radarrOverrides(FakeRadarrApi(), prefs: prefs),
      );
      addTearDown(container.dispose);
      expect(container.read(libraryQueryProvider).sort, MovieSortKey.added);
      await container.read(radarrContextProvider.future);
      container.read(libraryQueryProvider);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final q = container.read(libraryQueryProvider);
      expect(q.sort, MovieSortKey.title);
      expect(q.ascending, isTrue);
    });

    test('without a saved default the built-in one stays', () async {
      final container = ProviderContainer(
        overrides: radarrOverrides(FakeRadarrApi()),
      );
      addTearDown(container.dispose);
      await container.read(radarrContextProvider.future);
      container.read(libraryQueryProvider);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(libraryQueryProvider).sort, MovieSortKey.added);
      expect(container.read(libraryQueryProvider).ascending, isFalse);
    });
  });

  group('Missing', () {
    final now = DateTime.utc(2026, 5, 1, 12);

    RadarrMovie missing(
      int id,
      String title, {
      DateTime? inCinemas,
      DateTime? digital,
      DateTime? physical,
    }) => fakeMovie(
      id,
      title: title,
      hasFile: false,
      inCinemas: inCinemas,
      digital: digital,
      physical: physical,
      min: MinimumAvailability.announced,
    );

    test('newest release first, by the latest of the three dates', () {
      final library = [
        missing(1, 'Old', inCinemas: DateTime.utc(2019, 1, 1)),
        missing(
          2,
          'Cinema late',
          inCinemas: DateTime.utc(2020, 1, 1),
          digital: DateTime.utc(2022, 3, 1),
        ),
        missing(
          3,
          'Physical last',
          inCinemas: DateTime.utc(2018, 1, 1),
          digital: DateTime.utc(2019, 1, 1),
          physical: DateTime.utc(2024, 8, 9),
        ),
        missing(4, 'Digital only', digital: DateTime.utc(2023, 2, 2)),
      ];
      for (final scope in [WantedScope.released, WantedScope.allMissing]) {
        expect(_ids(wantedMovies(library, scope, now)), [3, 4, 2, 1]);
      }
    });

    test('ties break on title; movies without any date go last', () {
      final day = DateTime.utc(2024, 1, 1);
      final library = [
        missing(1, 'Zulu', digital: day),
        missing(2, 'Alpha', physical: day),
        missing(3, 'Undated'),
        missing(4, 'Mike', inCinemas: day, digital: day),
      ];
      expect(_ids(wantedMovies(library, WantedScope.released, now)), [
        2,
        4,
        1,
        3,
      ]);
    });

    test('only monitored movies without a file are listed', () {
      final library = [
        missing(1, 'A', digital: DateTime.utc(2024)),
        fakeMovie(2, digital: DateTime.utc(2025)), // has a file
        fakeMovie(
          3,
          hasFile: false,
          monitored: false,
          digital: DateTime.utc(2025),
        ),
      ];
      expect(_ids(wantedMovies(library, WantedScope.released, now)), [1]);
    });
  });

  group('Upcoming', () {
    RadarrMovie upcoming(
      int id,
      String title, {
      DateTime? inCinemas,
      DateTime? digital,
      DateTime? physical,
      MinimumAvailability min = MinimumAvailability.released,
    }) => fakeMovie(
      id,
      title: title,
      hasFile: false,
      inCinemas: inCinemas,
      digital: digital,
      physical: physical,
      min: min,
    );

    List<RadarrMovie> library() => [
      upcoming(1, 'Later', digital: DateTime.utc(2026, 9, 1)),
      upcoming(2, 'Soon', inCinemas: DateTime.utc(2026, 6, 10)),
      upcoming(3, 'No date'),
      // In cinemas already (past), digital ahead: ordered by the date ahead.
      upcoming(
        4,
        'Mid',
        inCinemas: DateTime.utc(2026, 3, 1),
        digital: DateTime.utc(2026, 7, 4),
        min: MinimumAvailability.released,
      ),
      // Only a date in the past, search not allowed yet: nothing ahead -> last.
      upcoming(5, 'Past only', inCinemas: DateTime.utc(2026, 3, 1)),
      upcoming(6, 'Alpha tie', digital: DateTime.utc(2026, 6, 10)),
    ];

    test('soonest release first, nulls last, ties by title', () {
      final now = DateTime.utc(2026, 5, 1, 12);
      final rows = wantedMovies(library(), WantedScope.upcoming, now);
      expect(_ids(rows), [6, 2, 4, 1, 3, 5]);
    });

    // Release dates are date-only values; "ahead" is decided against the
    // user's local calendar date. `now` is built from local wall-clock
    // components, so these hold whatever zone the host runs in. The far zones
    // (UTC-12, UTC+14) are run for real in `zones_test.dart`.
    test('the evening before a release date it is still ahead', () {
      final eve = DateTime(2026, 6, 9, 23, 30);
      // 'Soon' and 'Alpha tie' release on the 10th: ahead, ties by title.
      expect(_ids(wantedMovies(library(), WantedScope.upcoming, eve)), [
        6,
        2,
        4,
        1,
        3,
        5,
      ]);
    });

    test('on the release date that day is today: not behind', () {
      final morning = DateTime(2026, 6, 10, 0, 30);
      // 'Alpha tie' (digital on the 10th) has arrived, so it left the list;
      // 'Soon' (cinemas only, the 10th) is today and still keys the movie.
      expect(_ids(wantedMovies(library(), WantedScope.upcoming, morning)), [
        2,
        4,
        1,
        3,
        5,
      ]);
    });

    test('the day after it, that date no longer keys the movie', () {
      final next = DateTime(2026, 6, 11, 0, 30);
      // 'Soon' has nothing ahead any more: it goes after the dated ones, with
      // the other undated ones, by title.
      expect(_ids(wantedMovies(library(), WantedScope.upcoming, next)), [
        4,
        1,
        3,
        5,
        2,
      ]);
    });

    test('a date that is already behind does not key the movie', () {
      final lib = [
        upcoming(
          1,
          'Cinema behind, digital 20th',
          inCinemas: DateTime.utc(2026, 6, 9),
          digital: DateTime.utc(2026, 6, 20),
        ),
        upcoming(2, 'Digital 15th', digital: DateTime.utc(2026, 6, 15)),
      ];
      final now = DateTime.utc(2026, 6, 10, 23, 59);
      expect(_ids(wantedMovies(lib, WantedScope.upcoming, now)), [2, 1]);
    });
  });
}

RadarrMovie _withAdded(RadarrMovie m, DateTime? added) =>
    RadarrMovie.fromJson({...m.toJson(), 'added': added?.toIso8601String()});
