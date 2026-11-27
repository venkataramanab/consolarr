// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:test/test.dart';

Map<String, Object?> _raw([Map<String, Object?> extra = const {}]) => {
  'id': 7,
  'title': 'Example Show',
  'monitored': true,
  'qualityProfileId': 1,
  'tags': [1],
  'futureField': {'keep': 'me'},
  'seasons': [
    {'seasonNumber': 1, 'monitored': true},
    {'seasonNumber': 2, 'monitored': true},
    {'seasonNumber': 0, 'monitored': false},
  ],
  ...extra,
};

void main() {
  group('SonarrSeriesDetail', () {
    test('seasons are newest first; absent sections are null or empty', () {
      final d = SonarrSeriesDetail.fromJson(_raw());
      expect([for (final s in d.seasons) s.number], [2, 1, 0]);
      expect(d.overview, isNull);
      expect(d.rating, isNull);
      expect(d.cast, isEmpty);
      expect(d.externalLinks, isEmpty);
    });

    test('ratings v3 and v4 shapes; zero is no rating', () {
      final d = SonarrSeriesDetail.fromJson(
        _raw({
          'ratings': {'votes': 10, 'value': 8.4},
          'overview': '  ',
        }),
      );
      expect(d.rating?.value, 8.4);
      expect(d.overview, isNull);
      expect(
        SonarrSeriesDetail.fromJson(
          _raw({
            'ratings': {'value': 0},
          }),
        ).rating,
        isNull,
      );
      expect(
        SonarrSeriesDetail.fromJson(_raw({'ratings': 'bad'})).rating,
        isNull,
      );
    });

    test('editedPayload changes only the edited fields', () {
      final d = SonarrSeriesDetail.fromJson(_raw());
      final out = d.editedPayload(
        monitored: false,
        qualityProfileId: 4,
        tags: [1, 2],
        seasonMonitored: {2: false},
      );
      expect(out['monitored'], false);
      expect(out['qualityProfileId'], 4);
      expect(out['tags'], [1, 2]);
      expect(out['futureField'], {'keep': 'me'});
      expect(out['title'], 'Example Show');
      final seasons = out['seasons']! as List;
      expect((seasons[0]! as Map)['monitored'], true);
      expect((seasons[1]! as Map)['monitored'], false);
      expect((seasons[2]! as Map)['monitored'], false);
      // Original is untouched.
      expect(d.raw['monitored'], true);
      expect(d.editedPayload().toString(), d.raw.toString());
    });

    test('externalLinks: https on fixed hosts, validated ids only', () {
      final d = SonarrSeriesDetail.fromJson(
        _raw({
          'imdbId': 'tt0000001',
          'tvdbId': 55,
          'tmdbId': 66,
          'tvMazeId': 77,
          'website': 'https://evil.example/phish',
        }),
      );
      final uris = [for (final l in d.externalLinks) l.uri];
      expect(uris.length, 4);
      for (final u in uris) {
        expect(u.scheme, 'https');
        expect(u.host, isNot('evil.example'));
      }
      expect(
        {for (final u in uris) u.host},
        {'www.imdb.com', 'thetvdb.com', 'www.themoviedb.org', 'www.tvmaze.com'},
      );
    });

    test('malformed ids yield no link', () {
      for (final bad in [
        'tt1/../x',
        'javascript:alert(1)',
        'https://x.example',
        'tt',
        '',
      ]) {
        final d = SonarrSeriesDetail.fromJson(_raw({'imdbId': bad}));
        expect(d.externalLinks, isEmpty, reason: bad);
      }
      final d = SonarrSeriesDetail.fromJson(_raw({'tvdbId': 0, 'tmdbId': -1}));
      expect(d.externalLinks, isEmpty);
    });

    test('cast only when present; wrong types tolerated', () {
      final d = SonarrSeriesDetail.fromJson(
        _raw({
          'cast': [
            {'name': 'A. Actor'},
            {'name': ''},
            5,
          ],
        }),
      );
      expect(d.cast, ['A. Actor']);
    });

    test('missing id or title is a FormatException', () {
      expect(
        () => SonarrSeriesDetail.fromJson({'title': 'x'}),
        throwsFormatException,
      );
      expect(
        () => SonarrSeriesDetail.fromJson({'id': 1}),
        throwsFormatException,
      );
    });
  });

  group('SonarrEpisode', () {
    test('embedded series and file; hasFile from the file', () {
      final e = SonarrEpisode.fromJson({
        'id': 1,
        'seasonNumber': 1,
        'episodeNumber': 2,
        'episodeFile': {'id': 9, 'size': 5},
        'series': {'id': 7, 'title': 'Example Show'},
      });
      expect(e.hasFile, isTrue);
      expect(e.seriesId, 7);
      expect(e.series?.title, 'Example Show');
    });

    test('airDate fallback and malformed series', () {
      final e = SonarrEpisode.fromJson({
        'id': 1,
        'seriesId': 3,
        'airDate': '2026-05-02',
        'series': {'id': 'x'},
      });
      expect(e.series, isNull);
      expect(e.seriesId, 3);
      expect(e.airs, DateTime.parse('2026-05-02'));
      final f = SonarrEpisode.fromJson({
        'id': 2,
        'airDateUtc': '2026-05-02T01:00:00Z',
        'airDate': '2026-05-01',
      });
      expect(f.airs, DateTime.utc(2026, 5, 2, 1));
    });

    test('copyWith monitored; toJson round trip', () {
      final e = SonarrEpisode.fromJson({
        'id': 1,
        'seriesId': 2,
        'seasonNumber': 1,
        'episodeNumber': 1,
        'monitored': true,
        'hasFile': true,
      });
      expect(e.copyWith(monitored: false).monitored, isFalse);
      expect(SonarrEpisode.fromJson(e.toJson()), e);
      expect(e.toString(), 'SonarrEpisode(1)');
    });

    test('wrong id type is a FormatException', () {
      expect(() => SonarrEpisode.fromJson({'id': 'x'}), throwsFormatException);
    });
  });

  group('SonarrLookupResult', () {
    test('without an id the series is not in the library', () {
      final r = SonarrLookupResult.fromJson({
        'title': 'Example Show',
        'tvdbId': 5,
      });
      expect(r.inLibrary, isFalse);
      expect(r.libraryId, isNull);
      expect(r.toString(), isNot(contains('Example')));
    });
  });
}
