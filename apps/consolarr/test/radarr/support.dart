// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/data/radarr_prefs.dart';
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
  Result<List<RadarrQueueItem>> queueResult = const Result.ok([]);
  Result<List<RadarrRelease>> releasesResult = const Result.ok([]);
  Result<List<RadarrMovie>> lookupResult = const Result.ok([]);
  Result<void> removeResult = const Result.ok(null);
  Result<void> grabResult = const Result.ok(null);
  Result<RadarrMovie>? updateResult;
  Result<RadarrMovie>? addResult;
  Result<RadarrCommand> commandStart = const Result.ok(
    RadarrCommand(id: 1, status: CommandStatus.queued),
  );
  List<CommandStatus> commandScript = [
    CommandStatus.started,
    CommandStatus.completed,
  ];
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
  Future<Result<List<RadarrQueueItem>>> queue() async => queueResult;

  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required QueueBlocklist blocklist,
  }) async {
    calls.add('remove $id client=$removeFromClient ${blocklist.name}');
    return removeResult;
  }

  @override
  Future<Result<RadarrCommand>> searchMovies(List<int> ids) async {
    calls.add('search $ids');
    return commandStart;
  }

  @override
  Future<Result<RadarrCommand>> searchAllMissing() async {
    calls.add('searchAll');
    return commandStart;
  }

  @override
  Future<Result<RadarrCommand>> command(int id) async {
    final status =
        commandScript[commandCalls.clamp(0, commandScript.length - 1)];
    commandCalls++;
    return Result.ok(RadarrCommand(id: id, status: status));
  }

  @override
  Future<Result<List<RadarrRelease>>> releases(int movieId) async =>
      releasesResult;

  @override
  Future<Result<void>> grab(RadarrRelease release) async {
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
}) {
  final context = contextFor(api, cache: cache);
  return [
    radarrContextProvider.overrideWith((ref) async => context),
    radarrPrefsProvider.overrideWithValue(prefs ?? MemoryPrefs()),
    clockProvider.overrideWithValue(() => fixedNow),
    commandPollIntervalProvider.overrideWithValue(Duration.zero),
  ];
}
