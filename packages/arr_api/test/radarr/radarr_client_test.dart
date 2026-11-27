// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../support/fake_adapter.dart';

const _movie = {
  'id': 7,
  'title': 'Example Movie',
  'sortTitle': 'example movie',
  'year': 2024,
  'status': 'released',
  'overview': 'A fictional film.',
  'monitored': true,
  'minimumAvailability': 'released',
  'inCinemas': '2024-03-01T00:00:00Z',
  'digitalRelease': '2024-05-01T00:00:00Z',
  'qualityProfileId': 2,
  'tags': [1, 3],
  'hasFile': true,
  'sizeOnDisk': 4000000000,
  'runtime': 101,
  'tmdbId': 99,
  'youTubeTrailerId': 'abcDEF12345',
  'collection': {'title': 'Example Collection', 'tmdbId': 5},
  'ratings': {
    'imdb': {'value': 7.4},
  },
  'images': [
    {
      'coverType': 'poster',
      'url': '/MediaCover/7/poster.jpg?lastWrite=1',
      'remoteUrl': 'https://other.example/p.jpg',
    },
  ],
  'movieFile': {
    'id': 3,
    'size': 4000000000,
    'quality': {
      'quality': {'name': 'Bluray-1080p', 'resolution': 1080},
    },
    'mediaInfo': {'videoCodec': 'x265'},
  },
  'someFutureField': {'x': 1},
};

RadarrClient client(FakeAdapter a, {int? skipped}) => RadarrClient(
  dio: dioWith(a, base: 'https://radarr.example/prefix'),
  parseRunner: <T>(T Function() c) async => c(),
);

void main() {
  group('movies', () {
    test('parses fields, ignores unknown ones, keeps the prefix', () async {
      final adapter = FakeAdapter.fixed(jsonEncode([_movie]));
      final r = await client(adapter).movies();
      final m = r.valueOrNull!.single;
      expect(m.title, 'Example Movie');
      expect(m.hasFile, isTrue);
      expect(m.movieFile!.qualityName, 'Bluray-1080p');
      expect(m.collectionTitle, 'Example Collection');
      expect(m.rating, 7.4);
      expect(m.youTubeTrailerId, 'abcDEF12345');
      expect(m.minimumAvailability, MinimumAvailability.released);
      expect(adapter.requests.single.uri.path, '/prefix/api/v3/movie');
    });

    test('tolerates missing dates, file and collection', () async {
      final r = await client(
        FakeAdapter.fixed(
          jsonEncode([
            {'id': 1, 'title': 'Example Movie'},
          ]),
        ),
      ).movies();
      final m = r.valueOrNull!.single;
      expect(m.inCinemas, isNull);
      expect(m.movieFile, isNull);
      expect(m.hasFile, isFalse);
      expect(m.collectionTitle, isNull);
      expect(m.minimumAvailability, MinimumAvailability.unknown);
    });

    test('skips malformed rows and reports only the count', () async {
      var skipped = 0;
      final c = RadarrClient(
        dio: dioWith(
          FakeAdapter.fixed(
            jsonEncode([
              _movie,
              {'id': 'x', 'title': 3},
            ]),
          ),
        ),
        onRowsSkipped: (n) => skipped = n,
        parseRunner: <T>(T Function() c) async => c(),
      );
      expect((await c.movies()).valueOrNull, hasLength(1));
      expect(skipped, 1);
    });

    test('wrong shape and all-bad rows are parse_error', () async {
      for (final body in ['{"a":1}', '[1,2]', 'not json']) {
        final r = await client(FakeAdapter.fixed(body)).movies();
        expect(r.errorOrNull?.category, ErrorCategory.parseError, reason: body);
      }
    });

    test('large payloads are parsed through the runner', () async {
      var used = false;
      final big = jsonEncode([
        for (var i = 1; i < 800; i++) {..._movie, 'id': i},
      ]);
      expect(big.length, greaterThan(ArrClientBase.isolateThresholdBytes));
      final c = RadarrClient(
        dio: dioWith(FakeAdapter.fixed(big)),
        parseRunner: <T>(T Function() c) async {
          used = true;
          return c();
        },
      );
      expect((await c.movies()).valueOrNull, hasLength(799));
      expect(used, isTrue);
    });

    test('401 is auth_failed, 500 is server_error', () async {
      expect(
        (await client(
          FakeAdapter.fixed('', status: 401),
        ).movies()).errorOrNull?.category,
        ErrorCategory.authFailed,
      );
      expect(
        (await client(
          FakeAdapter.fixed('', status: 500),
        ).movies()).errorOrNull?.category,
        ErrorCategory.serverError,
      );
    });
  });

  test('artwork URL is server relative, prefixed and key free', () {
    final m = RadarrMovie.fromJson(_movie);
    final c = client(FakeAdapter.fixed('[]'));
    final uri = c.artworkUri(m, ArrImageType.poster)!;
    expect(uri.host, 'radarr.example');
    expect(uri.path, '/prefix/MediaCover/7/poster.jpg');
    expect(uri.toString(), isNot(contains('other.example')));
    expect(uri.toString().toLowerCase(), isNot(contains('apikey')));
  });

  group('systemStatus', () {
    test('v5 is fine, v2 is unsupported_version', () async {
      expect(
        (await client(
          FakeAdapter.fixed('{"version":"5.2.0.1"}'),
        ).systemStatus()).isOk,
        isTrue,
      );
      expect(
        (await client(
          FakeAdapter.fixed('{"version":"2.0.0.1"}'),
        ).systemStatus()).errorOrNull?.category,
        ErrorCategory.unsupportedVersion,
      );
      // v3 missing and a legacy endpoint that answers: too old.
      final legacy = FakeAdapter(
        (o) => o.uri.path.contains('/v3/')
            ? FakeAdapter.reply('', status: 404)
            : FakeAdapter.reply('{"version":"0.2.0.1"}'),
      );
      expect(
        (await client(legacy).systemStatus()).errorOrNull?.category,
        ErrorCategory.unsupportedVersion,
      );
      // Nothing there at all: a wrong address, not an old server.
      expect(
        (await client(
          FakeAdapter.fixed('', status: 404),
        ).systemStatus()).errorOrNull?.category,
        ErrorCategory.notFound,
      );
    });
  });

  group('calendar', () {
    test('sends the range as query and parses movies', () async {
      final adapter = FakeAdapter.fixed(jsonEncode([_movie]));
      final r = await client(adapter)
          .calendar(DateTime.utc(2024, 3), DateTime.utc(2024, 4));
      expect(r.valueOrNull, hasLength(1));
      final q = adapter.requests.single.uri.queryParameters;
      expect(q['start'], startsWith('2024-03-01'));
      expect(q['unmonitored'], 'true');
    });
  });

  group('updateMovie', () {
    test(
      'reads then writes the full object, changing only the asked fields',
      () async {
        final adapter = FakeAdapter((o) {
          if (o.method == 'GET') return FakeAdapter.reply(jsonEncode(_movie));
          return FakeAdapter.reply(o.data as String);
        });
        final r = await client(adapter).updateMovie(
          7,
          monitored: false,
          tags: [2],
          minimumAvailability: MinimumAvailability.inCinemas,
        );
        expect(r.valueOrNull!.monitored, isFalse);
        final put = adapter.requests.last;
        expect(put.method, 'PUT');
        final sent = jsonDecode(put.data as String) as Map<String, Object?>;
        expect(sent['someFutureField'], {'x': 1});
        expect(sent['tags'], [2]);
        expect(sent['minimumAvailability'], 'inCinemas');
        expect(sent['qualityProfileId'], 2);
        expect(sent.containsKey('path'), isFalse, reason: 'no move');
      },
    );

    test('a failed write is an error', () async {
      final adapter = FakeAdapter(
        (o) => o.method == 'GET'
            ? FakeAdapter.reply(jsonEncode(_movie))
            : FakeAdapter.reply('', status: 503),
      );
      final r = await client(adapter).updateMovie(7, monitored: true);
      expect(r.errorOrNull?.category, ErrorCategory.serverError);
    });
  });

  group('lookup and add', () {
    test('lookup passes the term as query; empty is an empty list', () async {
      final adapter = FakeAdapter.fixed('[]');
      final r = await client(adapter).lookup('tmdb:99');
      expect(r.valueOrNull, isEmpty);
      expect(adapter.requests.single.uri.queryParameters['term'], 'tmdb:99');
    });

    test(
      'add sends the options and collection monitor only if present',
      () async {
        final adapter = FakeAdapter.fixed(jsonEncode({..._movie, 'id': 9}));
        final lookup = RadarrMovie.fromJson({..._movie, 'id': 0});
        final c = client(adapter);
        final r = await c.addMovie(
          AddMovieRequest(
            lookup: lookup,
            qualityProfileId: 4,
            rootFolderPath: '/movies',
            minimumAvailability: MinimumAvailability.released,
            monitored: true,
            tags: const [1],
            searchForMovie: true,
            addCollection: true,
          ),
        );
        expect(r.valueOrNull!.id, 9);
        final sent = jsonDecode(adapter.requests.single.data as String) as Map;
        expect(sent['tmdbId'], 99);
        expect((sent['addOptions'] as Map)['searchForMovie'], isTrue);
        expect((sent['addOptions'] as Map)['monitor'], 'movieAndCollection');

        final noCollection = RadarrMovie.fromJson({
          'id': 0,
          'title': 'Example Movie',
          'tmdbId': 5,
        });
        await c.addMovie(
          AddMovieRequest(
            lookup: noCollection,
            qualityProfileId: 4,
            rootFolderPath: '/movies',
            minimumAvailability: MinimumAvailability.released,
            monitored: true,
            addCollection: true,
          ),
        );
        final sent2 = jsonDecode(adapter.requests.last.data as String) as Map;
        expect((sent2['addOptions'] as Map)['monitor'], 'movieOnly');
      },
    );

    test('adding a movie already in the library sends nothing', () async {
      final adapter = FakeAdapter.fixed('{}');
      final r = await client(adapter).addMovie(
        AddMovieRequest(
          lookup: RadarrMovie.fromJson(_movie),
          qualityProfileId: 1,
          rootFolderPath: '/m',
          minimumAvailability: MinimumAvailability.released,
          monitored: true,
        ),
      );
      expect(r.isErr, isTrue);
      expect(adapter.requests, isEmpty);
    });
  });

  group('queue', () {
    const record = {
      'id': 11,
      'movieId': 7,
      'title': 'Example.Movie.2024.1080p',
      'status': 'downloading',
      'trackedDownloadStatus': 'warning',
      'trackedDownloadState': 'importPending',
      'size': 1000,
      'sizeleft': 250,
      'timeleft': '01:02:03',
      'statusMessages': [
        {
          'title': 'x',
          'messages': ['No files found'],
        },
      ],
    };

    test('parses the paged envelope', () async {
      final r = await client(
        FakeAdapter.fixed(
          jsonEncode({
            'records': [record],
          }),
        ),
      ).queue();
      final i = r.valueOrNull!.single;
      expect(i.progress, 0.75);
      expect(i.timeLeft, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(i.messages, ['No files found']);
    });

    test('empty queue is ok', () async {
      final r = await client(FakeAdapter.fixed('{"records":[]}')).queue();
      expect(r.valueOrNull, isEmpty);
    });

    test('remove maps the choices to query parameters', () async {
      final adapter = FakeAdapter.fixed('');
      final c = client(adapter);
      await c.removeQueueItem(
        11,
        removeFromClient: true,
        blocklist: QueueBlocklist.blocklistAndSearch,
      );
      var q = adapter.requests.last.uri.queryParameters;
      expect(adapter.requests.last.method, 'DELETE');
      expect(q['removeFromClient'], 'true');
      expect(q['blocklist'], 'true');
      expect(q['skipRedownload'], 'false');
      await c.removeQueueItem(
        11,
        removeFromClient: false,
        blocklist: QueueBlocklist.none,
      );
      q = adapter.requests.last.uri.queryParameters;
      expect(q['blocklist'], 'false');
      expect(q['removeFromClient'], 'false');
    });
  });

  group('commands', () {
    test('search posts the ids; command status maps', () async {
      final adapter = FakeAdapter.fixed('{"id":5,"status":"queued"}');
      final c = client(adapter);
      final r = await c.searchMovies([7]);
      expect(r.valueOrNull!.status, CommandStatus.queued);
      final sent = jsonDecode(adapter.requests.single.data as String) as Map;
      expect(sent['name'], 'MoviesSearch');
      expect(sent['movieIds'], [7]);
      final all = await c.searchAllMissing();
      expect(all.isOk, isTrue);
      expect(
        (jsonDecode(adapter.requests.last.data as String) as Map)['name'],
        'MissingMoviesSearch',
      );
    });

    test('status values', () async {
      final r = await client(FakeAdapter.fixed('{"id":5,"status":"completed"}'))
          .command(5);
      expect(r.valueOrNull!.isFinished, isTrue);
    });
  });

  group('releases', () {
    const rel = {
      'guid': 'g1',
      'indexerId': 2,
      'title': 'Example.Movie.2024',
      'size': 123,
      'ageHours': 5.2,
      'seeders': 12,
      'protocol': 'torrent',
      'quality': {
        'quality': {'name': 'WEBDL-1080p', 'resolution': 1080},
      },
      'approved': false,
      'rejections': ['Not wanted'],
      'customFormats': [
        {'name': 'x265'},
      ],
    };

    test('parses releases and rejection reasons', () async {
      final r = await client(FakeAdapter.fixed(jsonEncode([rel]))).releases(7);
      final x = r.valueOrNull!.single;
      expect(x.rejected, isTrue);
      expect(x.rejections, ['Not wanted']);
      expect(x.customFormats, ['x265']);
      expect(x.ageHours, 5);
    });

    test('grab posts guid and indexer id only', () async {
      final adapter = FakeAdapter.fixed('{}');
      final x = RadarrRelease.fromJson(rel);
      expect((await client(adapter).grab(x)).isOk, isTrue);
      expect(jsonDecode(adapter.requests.single.data as String), {
        'guid': 'g1',
        'indexerId': 2,
      });
    });

    test('the API key never appears in a URL', () async {
      final adapter = FakeAdapter.fixed('[]');
      final dio = dioWith(adapter)..options.headers['X-Api-Key'] = 'secret-key';
      final c = RadarrClient(dio: dio);
      await c.releases(7);
      await c.movies();
      for (final o in adapter.requests) {
        expect(o.uri.toString(), isNot(contains('secret-key')));
      }
    });
  });

  test('network failures are mapped, not thrown', () async {
    final r = await client(
      FakeAdapter(
        (_) => throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
    ).movies();
    expect(r.errorOrNull?.category, ErrorCategory.timeout);
  });
}
