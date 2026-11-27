// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:core/core.dart';

/// One series with its episodes at a point in time.
///
/// With [offlineError] set the data is the last cached copy (fetched at
/// [fetchedAt]); every write action must then be disabled. [episodesError] is
/// set when the series loaded but its episode list did not (shown as a retry
/// row, the rest of the screen keeps working).
class DetailSnapshot {
  const DetailSnapshot({
    required this.detail,
    required this.episodes,
    required this.fetchedAt,
    this.downloading = const {},
    this.offlineError,
    this.episodesError,
  });

  final SonarrSeriesDetail detail;
  final List<SonarrEpisode> episodes;
  final DateTime fetchedAt;

  /// Episode ids that are in the download queue right now.
  final Set<int> downloading;
  final AppError? offlineError;
  final AppError? episodesError;

  bool get isOffline => offlineError != null;

  DetailSnapshot copyWith({
    SonarrSeriesDetail? detail,
    List<SonarrEpisode>? episodes,
    AppError? episodesError,
    bool clearEpisodesError = false,
    AppError? offlineError,
  }) => DetailSnapshot(
    detail: detail ?? this.detail,
    episodes: episodes ?? this.episodes,
    fetchedAt: fetchedAt,
    downloading: downloading,
    offlineError: offlineError ?? this.offlineError,
    episodesError: clearEpisodesError
        ? null
        : (episodesError ?? this.episodesError),
  );
}

/// Loads one series (SON-08) and keeps the last good copy for offline use
/// (SON-30).
class DetailRepository {
  DetailRepository({
    required SonarrApi api,
    required PayloadCache cache,
    required String serverId,
    required DateTime Function() clock,
  }) : _api = api,
       _cache = cache,
       _serverId = serverId,
       _clock = clock;

  final SonarrApi _api;
  final PayloadCache _cache;
  final String _serverId;
  final DateTime Function() _clock;

  /// Payload cache key of series [id].
  static String cacheKey(int id) => 'sonarr.series.$id';

  /// Fetches the live series. `not_found` is an answer (the series is gone,
  /// NAV-05), never hidden behind cached data; other reachability failures
  /// fall back to the cached copy. Auth, version and TLS failures never do.
  Future<Result<DetailSnapshot>> load(int id) async {
    final live = await _api.seriesDetail(id);
    final error = live.errorOrNull;
    if (error != null) {
      if (error.category != ErrorCategory.notFound &&
          kOfflineFallbackCategories.contains(error.category)) {
        final copy = await cached(id);
        if (copy != null) {
          return Result.ok(copy.copyWith(offlineError: error));
        }
      }
      return Result.err(error);
    }
    final detail = live.valueOrNull!;
    final at = _clock();
    final episodes = await _api.episodes(id);
    final downloading = await _downloading(id);
    final list = episodes.valueOrNull;
    if (list != null) await _store(id, detail, list, at);
    return Result.ok(
      DetailSnapshot(
        detail: detail,
        episodes: list ?? const [],
        fetchedAt: at,
        downloading: downloading,
        episodesError: episodes.errorOrNull,
      ),
    );
  }

  Future<Set<int>> _downloading(int seriesId) async {
    final queue = await _api.queue();
    return {
      for (final item in queue.valueOrNull ?? const <ArrQueueItem>[])
        if (item.seriesId == seriesId && item.episodeId != null)
          item.episodeId!,
    };
  }

  /// Re-reads only the episodes (after a season change or a failed load).
  Future<Result<DetailSnapshot>> reloadEpisodes(DetailSnapshot current) async {
    final episodes = await _api.episodes(current.detail.id);
    final list = episodes.valueOrNull;
    if (list == null) {
      return Result.ok(current.copyWith(episodesError: episodes.errorOrNull));
    }
    final next = current.copyWith(episodes: list, clearEpisodesError: true);
    await store(next);
    return Result.ok(next);
  }

  /// The cached copy without any network access, or null.
  Future<DetailSnapshot?> cached(int id) async {
    try {
      final hit = await _cache.read(_serverId, cacheKey(id));
      if (hit == null) return null;
      final map = jsonDecode(hit.json);
      if (map is! Map) return null;
      final series = map['series'];
      if (series is! Map) return null;
      final episodes = <SonarrEpisode>[];
      final rows = map['episodes'];
      if (rows is List) {
        for (final e in rows) {
          if (e is! Map) continue;
          try {
            episodes.add(SonarrEpisode.fromJson(e.cast<String, Object?>()));
          } on FormatException {
            // Skip a damaged entry; keep the rest.
          }
        }
      }
      return DetailSnapshot(
        detail: SonarrSeriesDetail.fromJson(series.cast<String, Object?>()),
        episodes: episodes,
        fetchedAt: hit.fetchedAt,
      );
    } on Object {
      return null;
    }
  }

  /// Writes [snapshot] as the last good copy (after a confirmed change).
  Future<void> store(DetailSnapshot snapshot) =>
      _store(snapshot.detail.id, snapshot.detail, snapshot.episodes, _clock());

  Future<void> _store(
    int id,
    SonarrSeriesDetail detail,
    List<SonarrEpisode> episodes,
    DateTime at,
  ) async {
    try {
      await _cache.write(
        _serverId,
        cacheKey(id),
        jsonEncode({
          'series': detail.toJson(),
          'episodes': [for (final e in episodes) e.toJson()],
        }),
        at,
      );
    } on Object {
      // The cache is best effort; a failed write must not fail the load.
    }
  }
}
