// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('availabilityOf', () {
    final now = DateTime.utc(2026, 5, 1, 12);
    final past = DateTime.utc(2026, 4, 1);
    final future = DateTime.utc(2026, 6, 1);
    final cases = <String, (RadarrMovie, Availability)>{
      'no dates': (fakeMovie(1), Availability.unannounced),
      'future cinema only': (
        fakeMovie(1, inCinemas: future),
        Availability.comingSoon,
      ),
      'future digital only': (
        fakeMovie(1, digital: future),
        Availability.comingSoon,
      ),
      'cinema passed, digital ahead': (
        fakeMovie(1, inCinemas: past, digital: future),
        Availability.inCinemas,
      ),
      'cinema passed only': (
        fakeMovie(1, inCinemas: past),
        Availability.inCinemas,
      ),
      'digital passed': (
        fakeMovie(1, inCinemas: past, digital: past, physical: future),
        Availability.releasedDigital,
      ),
      'physical passed': (
        fakeMovie(1, inCinemas: past, digital: past, physical: past),
        Availability.releasedPhysical,
      ),
      'physical passed, digital missing': (
        fakeMovie(1, physical: past),
        Availability.releasedPhysical,
      ),
      'cinema exactly now': (
        fakeMovie(1, inCinemas: now),
        Availability.inCinemas,
      ),
      'cinema one second ahead': (
        fakeMovie(1, inCinemas: now.add(const Duration(seconds: 1))),
        Availability.comingSoon,
      ),
    };
    cases.forEach((name, c) {
      test(name, () => expect(availabilityOf(c.$1, now), c.$2));
    });

    test('the same instant gives the same answer in any time zone', () {
      final utc = DateTime.utc(2026, 5, 1, 12);
      // 2026-05-01T12:00Z expressed with a +14 and a -12 offset.
      final plus14 = DateTime.parse('2026-05-02T02:00:00+14:00');
      final minus12 = DateTime.parse('2026-05-01T00:00:00-12:00');
      expect(plus14.toUtc(), utc);
      expect(minus12.toUtc(), utc);
      for (final d in [utc, plus14, minus12]) {
        expect(
          availabilityOf(fakeMovie(1, inCinemas: d), utc),
          Availability.inCinemas,
        );
        expect(
          availabilityOf(
            fakeMovie(1, inCinemas: d),
            utc.subtract(const Duration(seconds: 1)),
          ),
          Availability.comingSoon,
        );
      }
    });

    test('search eligibility follows minimum availability', () {
      final m = fakeMovie(
        1,
        inCinemas: DateTime.utc(2026, 4),
        min: MinimumAvailability.inCinemas,
      );
      expect(isReleasedForSearch(m, now), isTrue);
      final released = fakeMovie(
        1,
        inCinemas: DateTime.utc(2026, 4),
        min: MinimumAvailability.released,
      );
      expect(isReleasedForSearch(released, now), isFalse);
    });
  });

  group('applyQuery', () {
    final movies = [
      fakeMovie(1, title: 'Beta', year: 2001, rating: 5),
      fakeMovie(
        2,
        title: 'alpha',
        year: 1999,
        monitored: false,
        hasFile: false,
      ),
      fakeMovie(
        3,
        title: 'Gamma',
        year: 2010,
        collection: 'Example Saga',
        profile: 2,
      ),
      fakeMovie(
        4,
        title: 'Delta',
        tags: [7],
        min: MinimumAvailability.announced,
      ),
    ];
    List<int> ids(MovieQuery q) => [
      for (final m in applyQuery(movies, q)) m.id,
    ];

    test('title ascending and descending', () {
      expect(ids(const MovieQuery()), [2, 1, 4, 3]);
      expect(ids(const MovieQuery(ascending: false)), [3, 4, 1, 2]);
    });

    test('missing values sort last in both directions', () {
      final q = const MovieQuery(sort: MovieSortKey.rating);
      expect(ids(q).first, 1);
      expect(ids(q.copyWith(ascending: false)).first, 1);
    });

    test('search is case-insensitive and local', () {
      expect(ids(const MovieQuery(search: 'ALP')), [2]);
      expect(ids(const MovieQuery(search: 'zzz')), isEmpty);
    });

    test('every filter dimension', () {
      MovieQuery f(MovieFilter x) => MovieQuery(filter: x);
      expect(
        ids(f(const MovieFilter(monitored: MonitoredFilter.unmonitored))),
        [2],
      );
      expect(ids(f(const MovieFilter(file: FileFilter.missing))), [2]);
      expect(ids(f(const MovieFilter(file: FileFilter.downloaded))), [1, 4, 3]);
      expect(
        ids(
          f(const MovieFilter(availability: {MinimumAvailability.announced})),
        ),
        [4],
      );
      expect(ids(f(const MovieFilter(qualityProfiles: {2}))), [3]);
      expect(ids(f(const MovieFilter(tags: {7}))), [4]);
      expect(ids(f(const MovieFilter(collections: {'Example Saga'}))), [3]);
      expect(
        const MovieFilter(tags: {1}, file: FileFilter.missing).activeCount,
        2,
      );
    });

    test('filter survives a json round trip', () {
      const f = MovieFilter(
        monitored: MonitoredFilter.monitored,
        tags: {1, 2},
        availability: {MinimumAvailability.inCinemas},
        collections: {'Example Saga'},
      );
      expect(MovieFilter.fromJson(f.toJson()), f);
      expect(
        MovieFilter.fromJson({'monitored': 3, 'tags': 'x'}),
        MovieFilter.none,
      );
    });

    test('groups by first letter and by year', () {
      final sorted = applyQuery(movies, const MovieQuery());
      expect(
        [for (final g in groupMovies(sorted, MovieSortKey.title)) g.label],
        ['A', 'B', 'D', 'G'],
      );
      expect(groupMovies(sorted, MovieSortKey.size), hasLength(1));
      expect(groupOf(fakeMovie(9, title: '1917'), MovieSortKey.title), '#');
    });

    for (final n in [0, 1, 10000]) {
      test('$n movies: sort, filter and search stay correct', () {
        final list = fakeMovies(n);
        final watch = Stopwatch()..start();
        for (final key in MovieSortKey.values) {
          final out = applyQuery(list, MovieQuery(sort: key));
          expect(out, hasLength(n));
        }
        final found = applyQuery(list, const MovieQuery(search: 'movie 9999'));
        expect(found.length, n >= 9999 ? 1 : 0);
        expect(
          applyQuery(
            list,
            const MovieQuery(filter: MovieFilter(file: FileFilter.missing)),
          ),
          isEmpty,
        );
        expect(watch.elapsedMilliseconds, lessThan(5000));
      });
    }
  });
}
