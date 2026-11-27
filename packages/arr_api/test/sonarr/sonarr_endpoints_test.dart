// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../support/fake_adapter.dart';

const _base = 'https://sonarr.example/sonarr';
const _fakeKey = 'test-key-0000000000000000';

Future<T> _inline<T>(T Function() work) async => work();

SonarrClient _client(
  FakeAdapter a, {
  ParseRunner runner = _inline,
  void Function(int)? onSkipped,
}) => SonarrClient(
  dio: dioWith(a, base: _base),
  parseRunner: runner,
  onRowsSkipped: onSkipped,
);

String _seriesJson({int id = 7, Map<String, Object?> extra = const {}}) =>
    jsonEncode({
      'id': id,
      'title': 'Example Show',
      'monitored': true,
      'qualityProfileId': 1,
      'tags': [1],
      'unknownFuture': {'a': 1},
      'seasons': [
        {'seasonNumber': 1, 'monitored': true},
      ],
      ...extra,
    });

void _noKeyInUrls(FakeAdapter a) {
  for (final r in a.requests) {
    expect(r.uri.toString(), isNot(contains(_fakeKey)));
    expect(r.uri.toString().toLowerCase(), isNot(contains('apikey')));
  }
}

Future<void> _expectCategory(
  Future<Result<Object?>> Function(SonarrClient) call,
  ErrorCategory category,
  FakeAdapter a,
) async {
  final r = await call(_client(a));
  expect(r.errorOrNull?.category, category);
}

void main() {
  group('seriesDetail', () {
    test(
      'GET api/v3/series/{id} under a prefix; keeps the raw payload',
      () async {
        final a = FakeAdapter.fixed(_seriesJson());
        final r = await _client(a).seriesDetail(7);
        expect(r.valueOrNull?.id, 7);
        expect(r.valueOrNull?.raw['unknownFuture'], {'a': 1});
        final req = a.requests.single;
        expect(req.method, 'GET');
        expect(req.uri.path, '/sonarr/api/v3/series/7');
        _noKeyInUrls(a);
      },
    );

    test('404 is not_found; wrong type is parse_error', () async {
      await _expectCategory(
        (c) => c.seriesDetail(1),
        ErrorCategory.notFound,
        FakeAdapter.fixed('', status: 404),
      );
      await _expectCategory(
        (c) => c.seriesDetail(1),
        ErrorCategory.parseError,
        FakeAdapter.fixed('[]'),
      );
      await _expectCategory(
        (c) => c.seriesDetail(1),
        ErrorCategory.parseError,
        FakeAdapter.fixed('{"id":"x","title":1}'),
      );
    });
  });

  group('updateSeries', () {
    test('PUT with moveFiles=false and the payload as body', () async {
      final a = FakeAdapter.fixed(_seriesJson());
      final payload = {'id': 7, 'title': 'Example Show', 'monitored': false};
      final r = await _client(a).updateSeries(7, payload);
      expect(r.isOk, isTrue);
      final req = a.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/sonarr/api/v3/series/7');
      expect(req.uri.queryParameters['moveFiles'], 'false');
      expect(jsonDecode(req.data as String), payload);
      expect(req.uri.toString(), isNot(contains('moveFiles=true')));
    });

    test('5xx is server_error', () async {
      await _expectCategory(
        (c) => c.updateSeries(7, {}),
        ErrorCategory.serverError,
        FakeAdapter.fixed('', status: 503),
      );
    });
  });

  group('episodes', () {
    test('query includes seriesId and includeEpisodeFile', () async {
      final a = FakeAdapter.fixed(
        jsonEncode([
          {
            'id': 1,
            'seriesId': 7,
            'seasonNumber': 1,
            'episodeNumber': 1,
            'hasFile': true,
            'episodeFile': {
              'id': 5,
              'size': 10,
              'quality': {
                'quality': {'name': 'WEBDL-1080p'},
              },
            },
          },
        ]),
      );
      final r = await _client(a).episodes(7);
      expect(r.valueOrNull?.single.file?.qualityName, 'WEBDL-1080p');
      final q = a.requests.single.uri.queryParameters;
      expect(q['seriesId'], '7');
      expect(q['includeEpisodeFile'], 'true');
      expect(a.requests.single.uri.path, '/sonarr/api/v3/episode');
    });

    test(
      'malformed rows are skipped and counted; none valid is parse_error',
      () async {
        var skipped = 0;
        final a = FakeAdapter.fixed(
          jsonEncode([
            {'id': 1, 'seasonNumber': 1, 'episodeNumber': 1},
            {'id': 'bad'},
            5,
          ]),
        );
        final r = await _client(a, onSkipped: (n) => skipped = n).episodes(1);
        expect(r.valueOrNull?.length, 1);
        expect(skipped, 2);
        await _expectCategory(
          (c) => c.episodes(1),
          ErrorCategory.parseError,
          FakeAdapter.fixed(jsonEncode([5, 'x'])),
        );
        await _expectCategory(
          (c) => c.episodes(1),
          ErrorCategory.parseError,
          FakeAdapter.fixed('{}'),
        );
      },
    );
  });

  group('setEpisodesMonitored', () {
    test('PUT episode/monitor with ids and flag', () async {
      final a = FakeAdapter.fixed('{}');
      final r = await _client(a).setEpisodesMonitored([1, 2], monitored: true);
      expect(r.isOk, isTrue);
      final req = a.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/sonarr/api/v3/episode/monitor');
      expect(jsonDecode(req.data as String), {
        'episodeIds': [1, 2],
        'monitored': true,
      });
    });

    test('empty ids send nothing', () async {
      final a = FakeAdapter.fixed('{}');
      await _client(a).setEpisodesMonitored([], monitored: true);
      expect(a.requests, isEmpty);
    });

    for (final code in [404, 405]) {
      test('falls back to per-episode PUT on $code', () async {
        final a = FakeAdapter((o) {
          if (o.uri.path.endsWith('/episode/monitor')) {
            return FakeAdapter.reply('', status: code);
          }
          if (o.method == 'GET') {
            return FakeAdapter.reply(
              jsonEncode({'id': 3, 'monitored': false, 'extra': 1}),
            );
          }
          return FakeAdapter.reply('{}');
        });
        final r = await _client(a).setEpisodesMonitored([3], monitored: true);
        expect(r.isOk, isTrue);
        final put = a.requests.last;
        expect(put.method, 'PUT');
        expect(put.uri.path, '/sonarr/api/v3/episode/3');
        expect(jsonDecode(put.data as String), {
          'id': 3,
          'monitored': true,
          'extra': 1,
        });
      });
    }

    test('other errors are not swallowed', () async {
      await _expectCategory(
        (c) => c.setEpisodesMonitored([1], monitored: true),
        ErrorCategory.serverError,
        FakeAdapter.fixed('', status: 500),
      );
    });
  });

  group('calendar', () {
    test('start/end/unmonitored/includeSeries query', () async {
      final a = FakeAdapter.fixed('[]');
      // Empty array: nothing parses and nothing skipped.
      final r = await _client(a).calendar(
        start: DateTime.utc(2026, 5, 1),
        end: DateTime.utc(2026, 5, 31),
        includeUnmonitored: true,
      );
      expect(r.isOk, isTrue);
      final q = a.requests.single.uri.queryParameters;
      expect(q['start'], '2026-05-01');
      expect(q['end'], '2026-05-31');
      expect(q['unmonitored'], 'true');
      expect(q['includeSeries'], 'true');
      expect(a.requests.single.uri.path, '/sonarr/api/v3/calendar');
    });

    test('episode with embedded series parses', () async {
      final a = FakeAdapter.fixed(
        jsonEncode([
          {
            'id': 1,
            'seriesId': 7,
            'seasonNumber': 1,
            'episodeNumber': 2,
            'airDate': '2026-05-02',
            'series': {'id': 7, 'title': 'Example Show'},
          },
        ]),
      );
      final r = await _client(
        a,
      ).calendar(start: DateTime.utc(2026, 5), end: DateTime.utc(2026, 5, 3));
      expect(r.valueOrNull?.single.series?.title, 'Example Show');
      expect(a.requests.single.uri.queryParameters['unmonitored'], 'false');
    });
  });

  group('queue', () {
    Map<String, Object?> page(int p, int total, int n) => {
      'page': p,
      'pageSize': 200,
      'totalRecords': total,
      'records': [
        for (var i = 0; i < n; i++)
          {'id': p * 1000 + i, 'title': 'Example.Show.S01E01', 'size': 100},
      ],
    };

    test('reads pages until the total is reached', () async {
      final a = FakeAdapter((o) {
        final p = int.parse(o.uri.queryParameters['page']!);
        return FakeAdapter.reply(jsonEncode(page(p, 250, p == 1 ? 200 : 50)));
      });
      final r = await _client(a).queue();
      expect(r.valueOrNull?.length, 250);
      expect(a.requests.length, 2);
      final q = a.requests.first.uri.queryParameters;
      expect(q['includeSeries'], 'true');
      expect(q['includeEpisode'], 'true');
      expect(q['pageSize'], '200');
      expect(a.requests.first.uri.path, '/sonarr/api/v3/queue');
    });

    test('stops after 5 pages even when the server claims more', () async {
      final a = FakeAdapter((o) {
        final p = int.parse(o.uri.queryParameters['page']!);
        return FakeAdapter.reply(jsonEncode(page(p, 100000, 200)));
      });
      final r = await _client(a).queue();
      expect(a.requests.length, 5);
      expect(r.valueOrNull?.length, 1000);
    });

    test('a non-object body is parse_error', () async {
      await _expectCategory(
        (c) => c.queue(),
        ErrorCategory.parseError,
        FakeAdapter.fixed('[]'),
      );
    });

    test('empty queue is an empty list', () async {
      final r = await _client(FakeAdapter.fixed(jsonEncode(page(1, 0, 0))))
          .queue();
      expect(r.valueOrNull, isEmpty);
    });
  });

  group('removeQueueItem', () {
    Future<Uri> remove(ArrBlocklistChoice c, {bool client = true}) async {
      final a = FakeAdapter.fixed('{}');
      final r = await _client(a)
          .removeQueueItem(5, removeFromClient: client, blocklist: c);
      expect(r.isOk, isTrue);
      expect(a.requests.single.method, 'DELETE');
      expect(a.requests.single.uri.path, '/sonarr/api/v3/queue/5');
      return a.requests.single.uri;
    }

    test('none', () async {
      final q = (await remove(ArrBlocklistChoice.none)).queryParameters;
      expect(q['removeFromClient'], 'true');
      expect(q['blocklist'], 'false');
      expect(q['blacklist'], 'false');
      expect(q['skipRedownload'], 'false');
    });

    test('blocklist and search again', () async {
      final q = (await remove(
        ArrBlocklistChoice.blocklistAndSearch,
        client: false,
      )).queryParameters;
      expect(q['removeFromClient'], 'false');
      expect(q['blocklist'], 'true');
      expect(q['blacklist'], 'true');
      expect(q['skipRedownload'], 'false');
    });

    test('blocklist only', () async {
      final q = (await remove(ArrBlocklistChoice.blocklistOnly))
          .queryParameters;
      expect(q['blocklist'], 'true');
      expect(q['skipRedownload'], 'true');
    });

    test('404 is not_found', () async {
      await _expectCategory(
        (c) => c.removeQueueItem(
          1,
          removeFromClient: true,
          blocklist: ArrBlocklistChoice.none,
        ),
        ErrorCategory.notFound,
        FakeAdapter.fixed('', status: 404),
      );
    });
  });

  group('commands', () {
    test('startCommand POSTs name and params', () async {
      final a = FakeAdapter.fixed(
        jsonEncode({'id': 9, 'name': 'EpisodeSearch', 'status': 'queued'}),
      );
      final r = await _client(a).startCommand(
        const ArrCommandRequest('EpisodeSearch', {
          'episodeIds': [1],
        }),
      );
      expect(r.valueOrNull?.id, 9);
      expect(r.valueOrNull?.status, ArrCommandStatus.queued);
      final req = a.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/sonarr/api/v3/command');
      expect(jsonDecode(req.data as String), {
        'name': 'EpisodeSearch',
        'episodeIds': [1],
      });
    });

    test('command GET', () async {
      final a = FakeAdapter.fixed(jsonEncode({'id': 9, 'status': 'completed'}));
      final r = await _client(a).command(9);
      expect(r.valueOrNull?.isSuccess, isTrue);
      expect(a.requests.single.uri.path, '/sonarr/api/v3/command/9');
    });

    test('a command without an id is parse_error', () async {
      await _expectCategory(
        (c) => c.command(1),
        ErrorCategory.parseError,
        FakeAdapter.fixed('{"status":"queued"}'),
      );
    });
  });

  group('releases', () {
    test('episode query', () async {
      final a = FakeAdapter.fixed(
        jsonEncode([
          {'guid': 'g1', 'title': 'Example.Show.S01E01', 'indexerId': 2},
        ]),
      );
      final r = await _client(a).releases(episodeId: 4);
      expect(r.valueOrNull?.single.indexerId, 2);
      expect(a.requests.single.uri.queryParameters, {'episodeId': '4'});
      expect(a.requests.single.uri.path, '/sonarr/api/v3/release');
    });

    test('season query', () async {
      final a = FakeAdapter.fixed(
        jsonEncode([
          {'guid': 'g1', 'title': 'x'},
        ]),
      );
      await _client(a).releases(seriesId: 7, seasonNumber: 2);
      expect(a.requests.single.uri.queryParameters, {
        'seriesId': '7',
        'seasonNumber': '2',
      });
    });
  });

  group('grabRelease', () {
    test('POST guid and indexerId only', () async {
      final a = FakeAdapter.fixed('{}');
      final r = await _client(a)
          .grabRelease(const ArrRelease(guid: 'g1', title: 'T', indexerId: 3));
      expect(r.isOk, isTrue);
      final req = a.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/sonarr/api/v3/release');
      expect(jsonDecode(req.data as String), {'guid': 'g1', 'indexerId': 3});
    });

    test('a dropped connection is an error, never a retry', () async {
      final a = FakeAdapter((_) => FakeAdapter.dropped(''));
      final r = await _client(a)
          .grabRelease(const ArrRelease(guid: 'g1', title: 'T'));
      expect(r.isErr, isTrue);
      expect(a.requests.length, 1);
    });
  });

  group('wanted', () {
    String body(int page, int total) => jsonEncode({
      'page': page,
      'pageSize': 50,
      'totalRecords': total,
      'records': [
        {'id': 1, 'seriesId': 7, 'seasonNumber': 1, 'episodeNumber': 1},
      ],
    });

    test('missing path and paging query', () async {
      final a = FakeAdapter.fixed(body(2, 120));
      final r = await _client(a).wanted(SonarrWantedKind.missing, page: 2);
      expect(r.valueOrNull?.page, 2);
      expect(r.valueOrNull?.totalRecords, 120);
      expect(r.valueOrNull?.hasMore, isTrue);
      final u = a.requests.single.uri;
      expect(u.path, '/sonarr/api/v3/wanted/missing');
      expect(u.queryParameters['page'], '2');
      expect(u.queryParameters['pageSize'], '50');
      expect(u.queryParameters['includeSeries'], 'true');
      expect(u.queryParameters['monitored'], 'true');
    });

    test('cutoff path', () async {
      final a = FakeAdapter.fixed(body(1, 1));
      final r = await _client(a).wanted(SonarrWantedKind.cutoffUnmet);
      expect(a.requests.single.uri.path, '/sonarr/api/v3/wanted/cutoff');
      expect(r.valueOrNull?.hasMore, isFalse);
    });
  });

  group('lookup', () {
    test('term is sent as a query parameter, incl. id terms', () async {
      for (final term in ['example show', 'tvdb:123', 'imdb:tt0000001']) {
        final a = FakeAdapter.fixed(
          jsonEncode([
            {'title': 'Example Show', 'tvdbId': 123},
          ]),
        );
        final r = await _client(a).lookup(term);
        expect(r.valueOrNull?.single.inLibrary, isFalse);
        expect(a.requests.single.uri.queryParameters['term'], term);
        expect(a.requests.single.uri.path, '/sonarr/api/v3/series/lookup');
      }
    });

    test('a library series has an id', () async {
      final a = FakeAdapter.fixed(
        jsonEncode([
          {'id': 4, 'title': 'Example Show'},
        ]),
      );
      final r = await _client(a).lookup('x');
      expect(r.valueOrNull?.single.libraryId, 4);
    });
  });

  group('addSeries', () {
    final lookup = SonarrLookupResult.fromJson({
      'id': 0,
      'title': 'Example Show',
      'tvdbId': 123,
      'titleSlug': 'example-show',
      'images': <Object?>[],
      'seasons': [
        {'seasonNumber': 1, 'monitored': true},
      ],
    });
    const options = SonarrAddOptions(
      qualityProfileId: 2,
      rootFolderPath: '/media/tv',
      seriesType: SeriesType.anime,
      monitor: SonarrMonitorPreset.future,
      seasonFolder: false,
      monitored: false,
      tags: [3],
      searchForMissing: true,
    );

    FakeAdapter adapter({required int languageStatus}) => FakeAdapter((o) {
      if (o.uri.path.endsWith('/languageprofile')) {
        return languageStatus == 200
            ? FakeAdapter.reply(
                jsonEncode([
                  {'id': 4, 'name': 'English'},
                ]),
              )
            : FakeAdapter.reply('', status: languageStatus);
      }
      return FakeAdapter.reply(_seriesJson(id: 11));
    });

    test(
      'v3: copies lookup, drops id, adds options and languageProfileId',
      () async {
        final a = adapter(languageStatus: 200);
        final r = await _client(a).addSeries(lookup, options);
        expect(r.valueOrNull?.id, 11);
        final post = a.requests.last;
        expect(post.method, 'POST');
        expect(post.uri.path, '/sonarr/api/v3/series');
        final body = jsonDecode(post.data as String) as Map<String, Object?>;
        expect(body.containsKey('id'), isFalse);
        expect(body['titleSlug'], 'example-show');
        expect(body['tvdbId'], 123);
        expect(body['qualityProfileId'], 2);
        expect(body['rootFolderPath'], '/media/tv');
        expect(body['seriesType'], 'anime');
        expect(body['seasonFolder'], false);
        expect(body['monitored'], false);
        expect(body['tags'], [3]);
        expect(body['languageProfileId'], 4);
        expect(body['addOptions'], {
          'monitor': 'future',
          'searchForMissingEpisodes': true,
          'searchForCutoffUnmetEpisodes': false,
        });
      },
    );

    test(
      'v4: no languageprofile endpoint means no languageProfileId',
      () async {
        for (final code in [404, 405]) {
          final a = adapter(languageStatus: code);
          final r = await _client(a).addSeries(lookup, options);
          expect(r.isOk, isTrue);
          final body = jsonDecode(
            a.requests.last.data as String,
          ) as Map<String, Object?>;
          expect(body.containsKey('languageProfileId'), isFalse);
        }
      },
    );

    test('server rejection (400) is an error', () async {
      final a = FakeAdapter((o) {
        if (o.uri.path.endsWith('/languageprofile')) {
          return FakeAdapter.reply('', status: 404);
        }
        return FakeAdapter.reply('[]', status: 400);
      });
      final r = await _client(a).addSeries(lookup, options);
      expect(r.isErr, isTrue);
    });
  });

  group('createTag', () {
    test('POST label', () async {
      final a = FakeAdapter.fixed(jsonEncode({'id': 5, 'label': 'kids'}));
      final r = await _client(a).createTag('kids');
      expect(r.valueOrNull, const ArrTag(id: 5, label: 'kids'));
      expect(a.requests.single.method, 'POST');
      expect(a.requests.single.uri.path, '/sonarr/api/v3/tag');
      expect(jsonDecode(a.requests.single.data as String), {'label': 'kids'});
    });
  });

  group('faults and limits', () {
    final calls = <String, Future<Result<Object?>> Function(SonarrClient)>{
      'seriesDetail': (c) => c.seriesDetail(1),
      'episodes': (c) => c.episodes(1),
      'queue': (c) => c.queue(),
      'releases': (c) => c.releases(episodeId: 1),
      'lookup': (c) => c.lookup('x'),
      'command': (c) => c.command(1),
    };

    for (final e in calls.entries) {
      test(
        '${e.key}: 401 auth_failed, 5xx server_error, junk parse_error',
        () async {
          await _expectCategory(
            e.value,
            ErrorCategory.authFailed,
            FakeAdapter.fixed('', status: 401),
          );
          await _expectCategory(
            e.value,
            ErrorCategory.serverError,
            FakeAdapter.fixed('', status: 502),
          );
          await _expectCategory(
            e.value,
            ErrorCategory.parseError,
            FakeAdapter.fixed('<html>not json'),
          );
        },
      );

      test('${e.key}: drop mid-body and timeout are errors', () async {
        final dropped = await e.value(
          _client(FakeAdapter((_) => FakeAdapter.dropped('[{"id":'))),
        );
        expect(dropped.isErr, isTrue);
        final timeout = await e.value(
          _client(
            FakeAdapter(
              (o) => throw DioException.connectionTimeout(
                timeout: const Duration(seconds: 1),
                requestOptions: o,
              ),
            ),
          ),
        );
        expect(timeout.errorOrNull?.category, ErrorCategory.timeout);
      });
    }

    test(
      'large bodies are parsed through the runner, small ones inline',
      () async {
        var runs = 0;
        Future<T> spy<T>(T Function() work) async {
          runs++;
          return work();
        }

        final rows = [
          for (var i = 0; i < 2000; i++)
            {
              'id': i,
              'seriesId': 1,
              'seasonNumber': 1,
              'episodeNumber': i,
              'title': 'Example Episode $i',
              'overview': 'Fictional text ' * 4,
            },
        ];
        final big = jsonEncode(rows);
        expect(big.length, greaterThan(ArrClientBase.isolateThresholdBytes));
        final r = await _client(
          FakeAdapter.fixed(big),
          runner: spy,
        ).episodes(1);
        expect(r.valueOrNull?.length, 2000);
        expect(runs, 1);

        final small = jsonEncode(rows.take(3).toList());
        await _client(FakeAdapter.fixed(small), runner: spy).episodes(1);
        expect(runs, 1);
      },
    );

    test('the real isolate runner parses a large queue page', () async {
      final records = [
        for (var i = 0; i < 1500; i++)
          {'id': i, 'title': 'Example.Show.S01E01.${'x' * 40}', 'size': 5},
      ];
      final body = jsonEncode({
        'page': 1,
        'pageSize': 1500,
        'totalRecords': 1500,
        'records': records,
      });
      expect(body.length, greaterThan(ArrClientBase.isolateThresholdBytes));
      final c = SonarrClient(
        dio: dioWith(FakeAdapter.fixed(body), base: _base),
        parseRunner: isolateParseRunner,
      );
      final r = await c.queue();
      expect(r.valueOrNull?.length, 1500);
    });

    test('the real isolate runner parses large series, episode, calendar, '
        'release and lookup lists (no captured client)', () async {
      // A real HttpClient is unsendable; a ReceivePort in the adapter is the
      // same for Isolate.run, so a closure that captures the client fails.
      Future<SonarrClient> clientFor(String body) async => SonarrClient(
        dio: dioWith(_UnsendableAdapter(body), base: _base),
        parseRunner: isolateParseRunner,
      );
      String big(Map<String, Object?> Function(int i) row, int n) {
        final body = jsonEncode([for (var i = 1; i <= n; i++) row(i)]);
        expect(body.length, greaterThan(ArrClientBase.isolateThresholdBytes));
        return body;
      }

      final series = await (await clientFor(
        big(
          (i) => {
            'id': i,
            'title': 'Example Show $i ${'x' * 60}',
            'monitored': true,
          },
          1200,
        ),
      )).series();
      expect(series.errorOrNull, isNull);
      expect(series.valueOrNull?.length, 1200);

      final episodes = await (await clientFor(
        big(
          (i) => {
            'id': i,
            'seriesId': 1,
            'seasonNumber': 1,
            'episodeNumber': i,
            'title': 'Example Episode $i ${'x' * 60}',
          },
          1200,
        ),
      )).episodes(1);
      expect(episodes.errorOrNull, isNull);
      expect(episodes.valueOrNull?.length, 1200);

      final calendar = await (await clientFor(
        big(
          (i) => {
            'id': i,
            'seriesId': 1,
            'seasonNumber': 1,
            'episodeNumber': i,
            'title': 'Example Episode $i ${'x' * 60}',
          },
          1200,
        ),
      )).calendar(start: DateTime.utc(2026), end: DateTime.utc(2026, 2));
      expect(calendar.errorOrNull, isNull);
      expect(calendar.valueOrNull?.length, 1200);

      final releases = await (await clientFor(
        big(
          (i) => {
            'guid': 'guid-$i',
            'indexerId': 1,
            'title': 'Example.Show.S01E01.${'x' * 60}.$i',
          },
          1200,
        ),
      )).releases(episodeId: 1);
      expect(releases.errorOrNull, isNull);
      expect(releases.valueOrNull?.length, 1200);

      final lookup = await (await clientFor(
        big((i) => {'title': 'Example Show $i ${'x' * 60}', 'tvdbId': i}, 1200),
      )).lookup('example');
      expect(lookup.errorOrNull, isNull);
      expect(lookup.valueOrNull?.length, 1200);
    });

    test('a slow server is still answered', () async {
      final a = FakeAdapter((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return FakeAdapter.reply('{"id":1,"status":"started"}');
      });
      final r = await _client(a).command(1);
      expect(r.valueOrNull?.status, ArrCommandStatus.started);
    });

    test('no request URL ever carries the key', () async {
      final a = FakeAdapter.fixed('[]');
      final c = _client(a);
      await c.lookup('tvdb:1');
      await c.calendar(start: DateTime.utc(2026), end: DateTime.utc(2026, 2));
      await c.releases(episodeId: 1);
      _noKeyInUrls(a);
    });
  });
}

/// A fake adapter that, like the real `HttpClient` adapter, cannot be sent to
/// another isolate.
class _UnsendableAdapter extends FakeAdapter {
  _UnsendableAdapter(String body) : super((_) => FakeAdapter.reply(body));

  final ReceivePort port = ReceivePort();

  @override
  void close({bool force = false}) => port.close();
}
