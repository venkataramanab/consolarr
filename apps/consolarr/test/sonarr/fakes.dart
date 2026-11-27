// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'support.dart';

/// A [PayloadCache] in memory.
class MemoryPayloadCache implements PayloadCache {
  final Map<String, CachedPayload> entries = {};

  @override
  Future<CachedPayload?> read(String serverId, String key) async =>
      entries['$serverId/$key'];

  @override
  Future<void> write(
    String serverId,
    String key,
    String json,
    DateTime fetchedAt,
  ) async => entries['$serverId/$key'] = CachedPayload(
    json: json,
    fetchedAt: fetchedAt,
  );

  @override
  Future<void> deleteForServer(String serverId) async =>
      entries.removeWhere((k, _) => k.startsWith('$serverId/'));
}

/// A Sonarr API where every call returns a settable result (by default empty
/// or `not_found`) and counts its calls. Set a `Future` hook to delay or fail
/// a call; the `*Hook` callbacks run before the result is returned.
class ScriptedSonarrApi extends FakeSonarrApi {
  ScriptedSonarrApi({super.seriesResult, super.statusResult});

  Result<SonarrSeriesDetail> detailResult = const Result.err(
    AppError(ErrorCategory.notFound),
  );
  Result<SonarrSeriesDetail> updateResult = const Result.err(
    AppError(ErrorCategory.notFound),
  );
  Result<List<SonarrEpisode>> episodesResult = const Result.ok([]);
  Result<void> monitorResult = const Result.ok(null);
  Result<List<SonarrEpisode>> calendarResult = const Result.ok([]);
  Result<List<ArrQueueItem>> queueResult = const Result.ok([]);
  Result<void> removeResult = const Result.ok(null);
  Result<ArrCommand> startResult = const Result.ok(
    ArrCommand(id: 1, status: ArrCommandStatus.queued),
  );

  /// Consumed one per `command()` call; the last one repeats.
  List<Result<ArrCommand>> commandResults = const [
    Result.ok(ArrCommand(id: 1, status: ArrCommandStatus.completed)),
  ];
  Result<List<ArrRelease>> releasesResult = const Result.ok([]);
  Result<void> grabResult = const Result.ok(null);
  Result<ArrPage<SonarrEpisode>> wantedResult = const Result.ok(
    ArrPage(records: []),
  );
  Result<List<SonarrLookupResult>> lookupResult = const Result.ok([]);
  Result<SonarrSeriesDetail> addResult = const Result.err(
    AppError(ErrorCategory.notFound),
  );
  Result<ArrTag> createTagResult = const Result.ok(
    ArrTag(id: 99, label: 'new'),
  );
  Result<List<ArrQualityProfile>> profilesResult = const Result.ok([]);
  Result<List<ArrRootFolder>> foldersResult = const Result.ok([]);
  Result<List<ArrTag>> tagsResult = const Result.ok([]);

  final Map<String, int> calls = {};
  final List<Object?> sent = [];
  Future<void> Function(String name)? hook;

  int count(String name) => calls[name] ?? 0;

  Future<T> _run<T>(String name, T result, [Object? arg]) async {
    calls.update(name, (n) => n + 1, ifAbsent: () => 1);
    if (arg != null) sent.add(arg);
    await hook?.call(name);
    return result;
  }

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() =>
      _run('qualityProfiles', profilesResult);
  @override
  Future<Result<List<ArrRootFolder>>> rootFolders() =>
      _run('rootFolders', foldersResult);
  @override
  Future<Result<List<ArrTag>>> tags() => _run('tags', tagsResult);
  @override
  Future<Result<SonarrSeriesDetail>> seriesDetail(int id) =>
      _run('seriesDetail', detailResult, id);
  @override
  Future<Result<SonarrSeriesDetail>> updateSeries(
    int id,
    Map<String, Object?> payload,
  ) => _run('updateSeries', updateResult, payload);
  @override
  Future<Result<List<SonarrEpisode>>> episodes(int seriesId) =>
      _run('episodes', episodesResult, seriesId);
  @override
  Future<Result<void>> setEpisodesMonitored(
    List<int> episodeIds, {
    required bool monitored,
  }) => _run('setEpisodesMonitored', monitorResult, (episodeIds, monitored));
  @override
  Future<Result<List<SonarrEpisode>>> calendar({
    required DateTime start,
    required DateTime end,
    bool includeUnmonitored = false,
  }) => _run('calendar', calendarResult, (start, end, includeUnmonitored));
  @override
  Future<Result<List<ArrQueueItem>>> queue() => _run('queue', queueResult);
  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) =>
      _run('removeQueueItem', removeResult, (id, removeFromClient, blocklist));
  @override
  Future<Result<ArrCommand>> startCommand(ArrCommandRequest request) =>
      _run('startCommand', startResult, request);
  @override
  Future<Result<ArrCommand>> command(int id) {
    final n = count('command');
    final r =
        commandResults[n < commandResults.length
            ? n
            : commandResults.length - 1];
    return _run('command', r, id);
  }

  @override
  Future<Result<List<ArrRelease>>> releases({
    int? episodeId,
    int? seriesId,
    int? seasonNumber,
  }) => _run('releases', releasesResult, (episodeId, seriesId, seasonNumber));
  @override
  Future<Result<void>> grabRelease(ArrRelease release) =>
      _run('grabRelease', grabResult, release);
  @override
  Future<Result<ArrPage<SonarrEpisode>>> wanted(
    SonarrWantedKind kind, {
    int page = 1,
    int pageSize = 50,
  }) => _run('wanted', wantedResult, (kind, page));
  @override
  Future<Result<List<SonarrLookupResult>>> lookup(String term) =>
      _run('lookup', lookupResult, term);
  @override
  Future<Result<SonarrSeriesDetail>> addSeries(
    SonarrLookupResult lookup,
    SonarrAddOptions options,
  ) => _run('addSeries', addResult, (lookup, options));
  @override
  Future<Result<ArrTag>> createTag(String label) =>
      _run('createTag', createTagResult, label);
}

/// Overrides that put a [ScriptedSonarrApi] (or any API) behind the Sonarr
/// providers, with in-memory cache and preferences and a fixed clock.
List<Override> sonarrTestOverrides(
  SonarrApi api, {
  MemoryPayloadCache? cache,
  SonarrPrefsStore? prefs,
  DateTime? now,
  List<Duration> pollDelays = const [Duration.zero, Duration.zero],
}) {
  final clockNow = now ?? DateTime.utc(2026, 5, 1, 12);
  final payloads = cache ?? MemoryPayloadCache();
  return [
    sonarrSessionProvider.overrideWith(
      (ref) => SonarrSession(
        api: api,
        serverId: 'srv1',
        cache: payloads,
        clock: () => clockNow,
      ),
    ),
    sonarrPrefsStoreProvider.overrideWithValue(
      prefs ?? MemorySonarrPrefsStore(),
    ),
    clockProvider.overrideWithValue(() => clockNow),
  ];
}

// --- sample data (fictional) ----------------------------------------------------

SonarrEpisode fakeEpisode(
  int id, {
  int seriesId = 1,
  int season = 1,
  int? number,
  bool hasFile = false,
  bool monitored = true,
  DateTime? airs,
  SonarrSeries? series,
}) => SonarrEpisode(
  id: id,
  seriesId: seriesId,
  seasonNumber: season,
  episodeNumber: number ?? id,
  title: 'Example Episode $id',
  airDateUtc: airs ?? DateTime.utc(2026, 4, 1),
  hasFile: hasFile,
  monitored: monitored,
  file: hasFile
      ? SonarrEpisodeFile(
          id: id,
          size: 700 * 1024 * 1024,
          qualityName: 'WEBDL-1080p',
        )
      : null,
  series: series,
);

SonarrSeriesDetail fakeDetail(
  int id, {
  bool monitored = true,
  String? overview = 'An example overview.',
  int seasons = 2,
}) => SonarrSeriesDetail.fromJson({
  'id': id,
  'title': 'Example Show $id',
  'sortTitle': 'example show $id',
  'status': 'continuing',
  'overview': overview,
  'monitored': monitored,
  'network': 'Example Network',
  'path': '/media/tv/Example Show $id',
  'rootFolderPath': '/media/tv',
  'qualityProfileId': 1,
  'seriesType': 'standard',
  'seasonFolder': true,
  'tags': <int>[],
  'genres': ['Drama'],
  'ratings': {'votes': 100, 'value': 8.2},
  'imdbId': 'tt0000001',
  'tvdbId': 1000 + id,
  'images': [
    {'coverType': 'poster', 'url': '/MediaCover/$id/poster.jpg'},
    {'coverType': 'fanart', 'url': '/MediaCover/$id/fanart.jpg'},
  ],
  'seasons': [
    for (var s = 0; s < seasons; s++)
      {
        'seasonNumber': s + 1,
        'monitored': true,
        'statistics': {
          'episodeFileCount': 1,
          'totalEpisodeCount': 2,
          'episodeCount': 2,
        },
      },
  ],
  'statistics': {
    'seasonCount': seasons,
    'episodeFileCount': 2,
    'totalEpisodeCount': 4,
  },
});

ArrQueueItem fakeQueueItem(
  int id, {
  ArrQueueState state = ArrQueueState.downloading,
  double progress = 0.5,
  int? seriesId = 1,
  List<ArrStatusMessage> messages = const [],
}) => ArrQueueItem(
  id: id,
  title: 'Example.Show.S01E0$id.1080p.WEB-DL',
  state: state,
  size: 1000 * 1024 * 1024,
  sizeLeft: ((1 - progress) * 1000 * 1024 * 1024).round(),
  timeLeft: const Duration(minutes: 12),
  seriesId: seriesId,
  episodeId: id,
  seasonNumber: 1,
  episodeNumber: id,
  mediaTitle: 'Example Show $id',
  episodeTitle: 'Example Episode $id',
  downloadClient: 'Example Client',
  protocol: ArrProtocol.torrent,
  qualityName: 'WEBDL-1080p',
  messages: messages,
);

ArrRelease fakeRelease(
  int i, {
  List<String> rejections = const [],
  int size = 1024 * 1024 * 1024,
  int ageMinutes = 120,
  int? seeders = 10,
}) => ArrRelease(
  guid: 'guid-$i',
  title: 'Example.Show.S01E01.1080p.WEB-DL-GRP$i',
  indexerId: 1,
  indexer: 'Example Indexer',
  size: size,
  ageMinutes: ageMinutes,
  seeders: seeders,
  protocol: ArrProtocol.torrent,
  qualityName: 'WEBDL-1080p',
  resolution: 1080,
  source: 'webdl',
  approved: rejections.isEmpty,
  rejections: rejections,
  releaseWeight: i,
);
