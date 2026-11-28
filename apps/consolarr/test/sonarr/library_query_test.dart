// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/library_query.dart';
import 'package:flutter_test/flutter_test.dart';

SonarrSeries _s(
  int i, {
  String? title,
  int? year,
  String? network,
  SeriesStatus status = SeriesStatus.continuing,
  SeriesType type = SeriesType.standard,
  bool monitored = true,
  int profile = 1,
  List<int> tags = const [],
  DateTime? next,
  double rating = 0,
  int size = 0,
  List<String> genres = const [],
}) => SonarrSeries(
  id: i,
  title: title ?? 'Example Show $i',
  sortTitle: (title ?? 'Example Show $i').toLowerCase(),
  year: year,
  network: network,
  status: status,
  seriesType: type,
  monitored: monitored,
  qualityProfileId: profile,
  tags: tags,
  nextAiring: next,
  rating: rating,
  genres: genres,
  statistics: SeriesStatistics(sizeOnDisk: size),
);

List<int> _ids(List<SonarrSeries> l) => [for (final s in l) s.id];

void main() {
  const names = {1: 'HD', 2: 'SD'};

  group('search', () {
    test('matches title case-insensitively', () {
      final all = [
        _s(1, title: 'Alpha'),
        _s(2, title: 'Beta'),
        _s(3, title: 'alphabet'),
      ];
      final out = applyLibraryQuery(
        all,
        const LibraryQuery(search: 'ALPH'),
        names,
      );
      expect(_ids(out), [1, 3]);
    });

    test('no match gives an empty list', () {
      expect(
        applyLibraryQuery([_s(1)], const LibraryQuery(search: 'zzz'), names),
        isEmpty,
      );
    });
  });

  group('filter', () {
    final all = [
      _s(
        1,
        monitored: false,
        status: SeriesStatus.ended,
        profile: 2,
        tags: [5],
      ),
      _s(2, type: SeriesType.anime, tags: [6]),
      _s(3),
    ];
    List<int> run(LibraryFilter f) =>
        _ids(applyLibraryQuery(all, LibraryQuery(filter: f), names));

    test('monitored state', () {
      expect(run(const LibraryFilter(monitored: MonitoredFilter.unmonitored)), [
        1,
      ]);
      expect(run(const LibraryFilter(monitored: MonitoredFilter.monitored)), [
        2,
        3,
      ]);
    });
    test('status, type, profile and tags combine with AND across kinds', () {
      expect(run(const LibraryFilter(statuses: {SeriesStatus.ended})), [1]);
      expect(run(const LibraryFilter(types: {SeriesType.anime})), [2]);
      expect(run(const LibraryFilter(profileIds: {2})), [1]);
      expect(run(const LibraryFilter(tagIds: {5, 6})), [1, 2]);
      expect(
        run(const LibraryFilter(tagIds: {5, 6}, types: {SeriesType.anime})),
        [2],
      );
    });
    test('activeCount counts criteria, not values', () {
      expect(
        const LibraryFilter(
          tagIds: {1, 2},
          statuses: {SeriesStatus.ended},
        ).activeCount,
        2,
      );
    });
    test('json round trip', () {
      const f = LibraryFilter(
        monitored: MonitoredFilter.monitored,
        statuses: {SeriesStatus.ended},
        types: {SeriesType.daily},
        profileIds: {3},
        tagIds: {4},
      );
      expect(LibraryFilter.fromJson(f.toJson()), f);
      expect(LibraryFilter.fromJson('garbage'), const LibraryFilter());
    });
  });

  group('sort', () {
    test('title ascending and descending', () {
      final all = [_s(1, title: 'B'), _s(2, title: 'A'), _s(3, title: 'C')];
      const asc = LibraryQuery(sortKey: SeriesSortKey.title, ascending: true);
      expect(_ids(applyLibraryQuery(all, asc, names)), [2, 1, 3]);
      expect(
        _ids(applyLibraryQuery(all, asc.copyWith(ascending: false), names)),
        [3, 1, 2],
      );
    });

    test('missing values stay last in both directions', () {
      final all = [_s(1, year: 2010), _s(2), _s(3, year: 2001)];
      const asc = LibraryQuery(sortKey: SeriesSortKey.year, ascending: true);
      expect(_ids(applyLibraryQuery(all, asc, names)), [3, 1, 2]);
      expect(
        _ids(applyLibraryQuery(all, asc.copyWith(ascending: false), names)),
        [1, 3, 2],
      );
    });

    test('every key orders by its value', () {
      final all = [
        _s(
          1,
          network: 'B',
          size: 5,
          rating: 7,
          profile: 2,
          genres: ['Z'],
          next: DateTime(2026, 6),
        ),
        _s(
          2,
          network: 'A',
          size: 9,
          rating: 9,
          profile: 1,
          genres: ['A'],
          next: DateTime(2026, 5),
        ),
      ];
      List<int> by(SeriesSortKey k, {bool asc = true}) => _ids(
        applyLibraryQuery(all, LibraryQuery(sortKey: k, ascending: asc), names),
      );
      expect(by(SeriesSortKey.network), [2, 1]);
      expect(by(SeriesSortKey.size), [1, 2]);
      expect(by(SeriesSortKey.rating, asc: false), [2, 1]);
      expect(by(SeriesSortKey.qualityProfile), [2, 1]);
      expect(by(SeriesSortKey.genre), [2, 1]);
      expect(by(SeriesSortKey.nextAiring), [2, 1]);
    });

    test('sort default encoding round trips and rejects junk', () {
      final raw = encodeSort(SeriesSortKey.rating, ascending: false);
      expect(decodeSort(raw), (SeriesSortKey.rating, false));
      expect(decodeSort('nope'), isNull);
      expect(decodeSort(null), isNull);
    });
  });

  group('groups', () {
    test('title groups by first letter, others under #', () {
      final rows = applyLibraryQuery(
        [
          _s(1, title: 'Apple'),
          _s(2, title: 'avocado'),
          _s(3, title: '24'),
          _s(4, title: 'Beta'),
        ],
        const LibraryQuery(),
        names,
      );
      final g = groupSeries(rows, SeriesSortKey.title, names);
      expect(
        [for (final x in g) x.key],
        [const GroupText('#'), const GroupText('A'), const GroupText('B')],
      );
      expect([for (final x in g) x.series.length], [1, 2, 1]);
    });

    test('size, rating, next airing and unknown buckets', () {
      const gb = 1024 * 1024 * 1024;
      expect(
        groupKeyOf(_s(1, size: 5 * gb), SeriesSortKey.size, names),
        const GroupSize(0),
      );
      expect(
        groupKeyOf(_s(1, size: 20 * gb), SeriesSortKey.size, names),
        const GroupSize(1),
      );
      expect(
        groupKeyOf(_s(1, size: 60 * gb), SeriesSortKey.size, names),
        const GroupSize(2),
      );
      expect(
        groupKeyOf(_s(1, rating: 8.4), SeriesSortKey.rating, names),
        const GroupRating(8),
      );
      expect(
        groupKeyOf(_s(1), SeriesSortKey.rating, names),
        const GroupUnknown(),
      );
      expect(
        groupKeyOf(_s(1), SeriesSortKey.nextAiring, names),
        const GroupScheduled(false),
      );
      expect(
        groupKeyOf(_s(1, profile: 2), SeriesSortKey.qualityProfile, names),
        const GroupText('SD'),
      );
    });
  });

  group('extremes', () {
    test('0 and 1 items', () {
      expect(applyLibraryQuery(const [], const LibraryQuery(), names), isEmpty);
      expect(groupSeries(const [], SeriesSortKey.title, names), isEmpty);
      expect(_ids(applyLibraryQuery([_s(1)], const LibraryQuery(), names)), [
        1,
      ]);
    });

    test('10,000 items filter, sort and group within a second', () {
      final all = [
        for (var i = 1; i <= 10000; i++)
          _s(
            i,
            title: 'Show ${(i * 7919) % 10000}',
            year: 1990 + i % 35,
            monitored: i.isEven,
          ),
      ];
      final watch = Stopwatch()..start();
      final rows = applyLibraryQuery(
        all,
        const LibraryQuery(
          search: 'show',
          sortKey: SeriesSortKey.year,
          filter: LibraryFilter(monitored: MonitoredFilter.monitored),
        ),
        names,
      );
      final groups = groupSeries(rows, SeriesSortKey.year, names);
      watch.stop();
      expect(rows.length, 5000);
      expect(groups.length, 35);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
