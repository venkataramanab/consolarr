// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/data/radarr_prefs.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/features/radarr/data/radarr_repository.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// A fake Radarr API with scripted answers (fake data only).
class FakeRadarrApi with EmptyArrLists implements RadarrApi {
  FakeRadarrApi({
    this.moviesResult = const Result.ok([]),
    this.profiles = const [ArrQualityProfile(id: 1, name: 'HD-1080p')],
  });

  Result<List<RadarrMovie>> moviesResult;
  Result<RadarrMovie>? movieResult;
  Result<List<RadarrMovie>> calendarResult = const Result.ok([]);
  Result<List<ArrQueueItem>> queueResult = const Result.ok([]);
  Result<List<ArrRelease>> releasesResult = const Result.ok([]);
  Result<List<RadarrMovie>> lookupResult = const Result.ok([]);
  Result<void> removeResult = const Result.ok(null);
  Result<void> grabResult = const Result.ok(null);
  Result<RadarrMovie>? updateResult;
  Result<RadarrMovie>? addResult;
  Result<ArrCommand> commandStart = const Result.ok(
    ArrCommand(id: 1, status: ArrCommandStatus.queued),
  );
  List<ArrCommandStatus> commandScript = [
    ArrCommandStatus.started,
    ArrCommandStatus.completed,
  ];
  List<ArrRootFolder> rootFoldersResult = const [];
  final List<ArrQualityProfile> profiles;
  final List<String> calls = [];
  int moviesCalls = 0;
  int commandCalls = 0;

  @override
  ServiceKind get kind => ServiceKind.radarr;

  @override
  Future<Result<ArrSystemStatus>> systemStatus() async =>
      const Result.ok(ArrSystemStatus(version: '5.0.0.0'));

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() async =>
      Result.ok(profiles);

  @override
  Future<Result<List<ArrRootFolder>>> rootFolders() async =>
      Result.ok(rootFoldersResult);

  @override
  Future<Result<List<RadarrMovie>>> movies() async {
    moviesCalls++;
    return moviesResult;
  }

  @override
  Future<Result<RadarrMovie>> movie(int id) async =>
      movieResult ??
      Result.ok(
        (moviesResult.valueOrNull ?? const <RadarrMovie>[]).firstWhere(
          (m) => m.id == id,
          orElse: () => throw StateError('no movie $id'),
        ),
      );

  @override
  Future<Result<List<RadarrMovie>>> calendar(DateTime s, DateTime e) async =>
      calendarResult;

  @override
  Future<Result<RadarrMovie>> updateMovie(
    int id, {
    bool? monitored,
    int? qualityProfileId,
    MinimumAvailability? minimumAvailability,
    List<int>? tags,
  }) async {
    calls.add(
      'update $id monitored=$monitored profile=$qualityProfileId '
      'min=${minimumAvailability?.name} tags=$tags',
    );
    return updateResult ?? movie(id);
  }

  @override
  Future<Result<List<RadarrMovie>>> lookup(String term) async {
    calls.add('lookup $term');
    return lookupResult;
  }

  @override
  Future<Result<RadarrMovie>> addMovie(AddMovieRequest request) async {
    calls.add(
      'add search=${request.searchForMovie} collection=${request.addCollection}'
      ' root=${request.rootFolderPath}',
    );
    return addResult ?? Result.ok(fakeMovie(99));
  }

  @override
  Future<Result<List<ArrQueueItem>>> queue() async => queueResult;

  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) async {
    calls.add('remove $id client=$removeFromClient ${blocklist.name}');
    return removeResult;
  }

  @override
  Future<Result<ArrCommand>> searchMovies(List<int> ids) async {
    calls.add('search $ids');
    return commandStart;
  }

  @override
  Future<Result<ArrCommand>> searchAllMissing() async {
    calls.add('searchAll');
    return commandStart;
  }

  @override
  Future<Result<ArrCommand>> command(int id) async {
    final status =
        commandScript[commandCalls.clamp(0, commandScript.length - 1)];
    commandCalls++;
    return Result.ok(ArrCommand(id: id, status: status));
  }

  @override
  Future<Result<List<ArrRelease>>> releases(int movieId) async =>
      releasesResult;

  @override
  Future<Result<void>> grab(ArrRelease release) async {
    calls.add('grab ${release.guid}');
    return grabResult;
  }

  @override
  Uri? artworkUri(RadarrMovie movie, ArrImageType type) => null;
}

RadarrMovie fakeMovie(
  int i, {
  String? title,
  bool monitored = true,
  bool hasFile = true,
  DateTime? inCinemas,
  DateTime? digital,
  DateTime? physical,
  int? year,
  int profile = 1,
  String? collection,
  MinimumAvailability min = MinimumAvailability.released,
  List<int> tags = const [],
  double? rating,
  int size = 3 * 1024 * 1024 * 1024,
  List<String> genres = const ['Drama'],
}) => RadarrMovie(
  id: i,
  title: title ?? 'Example Movie $i',
  sortTitle: (title ?? 'Example Movie $i').toLowerCase(),
  year: year ?? 1990 + i % 35,
  monitored: monitored,
  hasFile: hasFile,
  sizeOnDisk: hasFile ? size : 0,
  inCinemas: inCinemas,
  digitalRelease: digital,
  physicalRelease: physical,
  qualityProfileId: profile,
  collectionTitle: collection,
  minimumAvailability: min,
  tags: tags,
  rating: rating,
  genres: genres,
  added: DateTime.utc(2024, 1, 1).add(Duration(days: i)),
  images: [
    ArrImage(type: ArrImageType.poster, url: '/MediaCover/$i/poster.jpg'),
  ],
);

List<RadarrMovie> fakeMovies(int n) => [
  for (var i = 1; i <= n; i++) fakeMovie(i),
];

/// In-memory payload cache.
class MemoryPayloadCache implements PayloadCache {
  final Map<String, CachedPayload> rows = {};
  String _k(String s, String k) => '$s|$k';

  @override
  Future<CachedPayload?> read(String serverId, String key) async =>
      rows[_k(serverId, key)];

  @override
  Future<void> write(
    String serverId,
    String key,
    String json,
    DateTime fetchedAt,
  ) async =>
      rows[_k(serverId, key)] = CachedPayload(json: json, fetchedAt: fetchedAt);

  @override
  Future<void> deleteForServer(String serverId) async =>
      rows.removeWhere((k, _) => k.startsWith('$serverId|'));

  @override
  Future<void> delete(String serverId, String key) async =>
      rows.remove(_k(serverId, key));

  @override
  Future<void> pruneKeys(String keyPrefix, Set<String> keepServerIds) async =>
      rows.removeWhere(
        (k, _) =>
            k.contains('|$keyPrefix') &&
            !keepServerIds.contains(k.split('|').first),
      );
}

class MemoryPrefs implements RadarrPrefs {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

String moviesJson(List<RadarrMovie> m) =>
    jsonEncode([for (final x in m) x.toJson()]);

final fixedNow = DateTime.utc(2026, 5, 1, 12);

/// A context over [api] with an in-memory cache.
RadarrContext contextFor(FakeRadarrApi api, {MemoryPayloadCache? cache}) =>
    RadarrContext(
      api: api,
      repository: RadarrRepository(
        api: api,
        cache: cache ?? MemoryPayloadCache(),
        serverId: 'srv1',
        clock: () => fixedNow,
      ),
      serverId: 'srv1',
      dio: Dio(),
    );

/// Provider overrides serving [api] as the active Radarr server.
List<Override> radarrOverrides(
  FakeRadarrApi api, {
  MemoryPayloadCache? cache,
  MemoryPrefs? prefs,
  bool includeContext = true,
  MovieRunner? movieRunner,
  DateTime Function()? clock,
}) {
  final context = contextFor(api, cache: cache);
  return [
    if (includeContext)
      radarrContextProvider.overrideWith((ref) async => context),
    radarrPrefsProvider.overrideWithValue(prefs ?? MemoryPrefs()),
    clockProvider.overrideWithValue(clock ?? () => fixedNow),
    appLockedProvider.overrideWithValue(false),
    commandPollIntervalProvider.overrideWithValue(Duration.zero),
    // Big libraries are filtered inline: a real isolate never completes under
    // the widget tester's fake clock.
    movieRunnerProvider.overrideWithValue(
      movieRunner ?? <T>(T Function() c) async => c(),
    ),
  ];
}

/// A queue item of the fake server.
ArrQueueItem fakeQueueItem(
  int id, {
  String title = 'Example.Movie.2024.1080p',
  int? movieId,
  ArrQueueState state = ArrQueueState.downloading,
  int size = 1000,
  int sizeLeft = 500,
  String? downloadId,
  List<ArrStatusMessage> messages = const [],
}) => ArrQueueItem(
  id: id,
  title: title,
  movieId: movieId,
  state: state,
  size: size,
  sizeLeft: sizeLeft,
  downloadId: downloadId,
  messages: messages,
);

/// A release of the fake server.
ArrRelease fakeRelease(
  String guid, {
  int indexerId = 1,
  String title = 'Example.Movie.2024.1080p.WEB-DL',
  int size = 4 * 1024 * 1024 * 1024,
  int ageMinutes = 60 * 5,
  int? seeders = 10,
  bool approved = true,
  List<String> rejections = const [],
  ArrProtocol protocol = ArrProtocol.torrent,
  int? resolution = 1080,
  String? indexer = 'Example Indexer',
}) => ArrRelease(
  guid: guid,
  title: title,
  indexerId: indexerId,
  indexer: indexer,
  size: size,
  ageMinutes: ageMinutes,
  seeders: seeders,
  protocol: protocol,
  resolution: resolution,
  qualityName: resolution == null ? null : 'WEBDL-${resolution}p',
  approved: approved,
  rejections: rejections,
);
