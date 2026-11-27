// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

Map<String, Object?> fullSeries({int id = 1}) => {
  'id': id,
  'title': 'Example Show $id',
  'sortTitle': 'example show $id',
  'year': 2019,
  'status': 'continuing',
  'monitored': true,
  'network': 'Example Network',
  'seriesType': 'standard',
  'nextAiring': '2030-01-02T03:04:05Z',
  'added': '2020-05-06T07:08:09Z',
  'qualityProfileId': 4,
  'tags': [1, 2],
  'overview': 'ignored text',
  'unknownFutureField': {'a': 1},
  'images': [
    {
      'coverType': 'poster',
      'url': '/MediaCover/$id/poster.jpg?lastWrite=637000000000000000',
      'remoteUrl': 'https://images.example/p.jpg',
    },
    {'coverType': 'fanart', 'url': '/MediaCover/$id/fanart.jpg'},
  ],
  'statistics': {
    'seasonCount': 3,
    'episodeFileCount': 20,
    'episodeCount': 24,
    'totalEpisodeCount': 30,
    'sizeOnDisk': 123456789012,
    'percentOfEpisodes': 83.3,
  },
};

void main() {
  group('SonarrSeries.fromJson', () {
    test('parses a full v3/v4 record and ignores unknown fields', () {
      final s = SonarrSeries.fromJson(fullSeries());
      expect(s.id, 1);
      expect(s.title, 'Example Show 1');
      expect(s.sortTitle, 'example show 1');
      expect(s.year, 2019);
      expect(s.status, SeriesStatus.continuing);
      expect(s.monitored, isTrue);
      expect(s.network, 'Example Network');
      expect(s.seriesType, SeriesType.standard);
      expect(s.nextAiring, DateTime.utc(2030, 1, 2, 3, 4, 5));
      expect(s.added, DateTime.utc(2020, 5, 6, 7, 8, 9));
      expect(s.qualityProfileId, 4);
      expect(s.tags, [1, 2]);
      expect(s.images, hasLength(2));
      expect(s.images.first.type, SonarrImageType.poster);
      expect(s.statistics.episodeFileCount, 20);
      expect(s.statistics.totalEpisodeCount, 30);
      expect(s.statistics.sizeOnDisk, 123456789012);
      expect(s.statistics.percentOfEpisodes, closeTo(83.3, 0.001));
    });

    test('tolerates a minimal record (only id and title)', () {
      final s = SonarrSeries.fromJson({'id': 7, 'title': 'Example Show 7'});
      expect(s.sortTitle, 'Example Show 7');
      expect(s.year, isNull);
      expect(s.status, SeriesStatus.unknown);
      expect(s.seriesType, SeriesType.unknown);
      expect(s.monitored, isFalse);
      expect(s.tags, isEmpty);
      expect(s.images, isEmpty);
      expect(s.statistics.episodeCount, 0);
      expect(s.nextAiring, isNull);
    });

    test('unknown enum values map to unknown; year 0 means unknown', () {
      final s = SonarrSeries.fromJson({
        'id': 1,
        'title': 'x',
        'status': 'something-new',
        'seriesType': 'weird',
        'year': 0,
      });
      expect(s.status, SeriesStatus.unknown);
      expect(s.seriesType, SeriesType.unknown);
      expect(s.year, isNull);
    });

    test('statistics may carry doubles and nulls', () {
      final s = SonarrSeries.fromJson({
        'id': 1,
        'title': 'x',
        'statistics': {'sizeOnDisk': 10.0, 'episodeCount': null},
      });
      expect(s.statistics.sizeOnDisk, 10);
      expect(s.statistics.episodeCount, 0);
    });

    test('wrong types for required fields are a parse_error', () {
      for (final bad in <Map<String, Object?>>[
        {'id': '1', 'title': 'x'},
        {'id': 1, 'title': 5},
        {'title': 'x'},
        {'id': 1},
      ]) {
        expect(
          () => SonarrSeries.fromJson(bad),
          throwsA(isA<FormatException>()),
          reason: '$bad',
        );
      }
    });

    test('wrong types for optional fields are tolerated as absent', () {
      final s = SonarrSeries.fromJson({
        'id': 1,
        'title': 'x',
        'year': 'abc',
        'monitored': 'yes',
        'tags': 'nope',
        'images': 5,
        'statistics': 'bad',
        'nextAiring': 12,
      });
      expect(s.year, isNull);
      expect(s.tags, isEmpty);
      expect(s.images, isEmpty);
      expect(s.nextAiring, isNull);
    });

    test('toJson round-trips through fromJson (cache format)', () {
      final s = SonarrSeries.fromJson(fullSeries());
      final again = SonarrSeries.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
      );
      expect(again, s);
      expect(jsonEncode(s.toJson()), isNot(contains('images.example')));
    });
  });

  group('parseSeriesList', () {
    test('parses an array', () {
      final list = parseSeriesList(
        jsonEncode([fullSeries(), fullSeries(id: 2)]),
      );
      expect(list.map((s) => s.id), [1, 2]);
    });

    test('rejects non-arrays and malformed JSON with FormatException', () {
      expect(() => parseSeriesList('{"a":1}'), throwsFormatException);
      expect(() => parseSeriesList('not json'), throwsFormatException);
      expect(() => parseSeriesList('[1]'), throwsFormatException);
    });
  });

  group('ArrSystemStatus', () {
    test('majorVersion is derived from the version string', () {
      expect(const ArrSystemStatus(version: '4.0.9.2244').majorVersion, 4);
      expect(const ArrSystemStatus(version: '3.0.10').majorVersion, 3);
      expect(const ArrSystemStatus(version: 'weird').majorVersion, isNull);
    });
  });

  test('parse errors use the parse_error category constant', () {
    expect(ErrorCategory.parseError.code, 'parse_error');
  });
}
