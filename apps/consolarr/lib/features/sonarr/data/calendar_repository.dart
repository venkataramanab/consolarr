// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:core/core.dart';

/// Episodes airing in a window, at a point in time.
///
/// When [offlineError] is set the episodes are the last cached copy (fetched
/// at [fetchedAt]) and the live refresh failed with that error.
class CalendarSnapshot {
  const CalendarSnapshot({
    required this.episodes,
    required this.fetchedAt,
    this.offlineError,
  });

  final List<SonarrEpisode> episodes;
  final DateTime fetchedAt;
  final AppError? offlineError;

  bool get isOffline => offlineError != null;
}

/// Loads the calendar window and keeps the last good window for the offline
/// view (SON-30): one payload under `sonarr.calendar` holding the window, the
/// unmonitored flag and the episodes.
class CalendarRepository {
  CalendarRepository({
    required SonarrApi api,
    required PayloadCache cache,
    required String serverId,
    required DateTime Function() clock,
  }) : _api = api,
       _cache = cache,
       _serverId = serverId,
       _clock = clock;

  static const cacheKey = 'sonarr.calendar';

  final SonarrApi _api;
  final PayloadCache _cache;
  final String _serverId;
  final DateTime Function() _clock;

  /// Fetches `[start, end)`. On a reachability failure returns the cached
  /// window when it covers the request; never on auth, version or TLS errors.
  Future<Result<CalendarSnapshot>> load({
    required DateTime start,
    required DateTime end,
    required bool includeUnmonitored,
  }) async {
    final live = await _api.calendar(
      start: start,
      end: end,
      includeUnmonitored: includeUnmonitored,
    );
    final items = live.valueOrNull;
    if (items != null) {
      final at = _clock();
      await _store(start, end, includeUnmonitored, items, at);
      return Result.ok(CalendarSnapshot(episodes: items, fetchedAt: at));
    }
    final error = live.errorOrNull!;
    if (kOfflineFallbackCategories.contains(error.category)) {
      final copy = await _cached(start, end, includeUnmonitored);
      if (copy != null) {
        return Result.ok(
          CalendarSnapshot(
            episodes: copy.episodes,
            fetchedAt: copy.fetchedAt,
            offlineError: error,
          ),
        );
      }
    }
    return Result.err(error);
  }

  Future<CalendarSnapshot?> _cached(
    DateTime start,
    DateTime end,
    bool includeUnmonitored,
  ) async {
    try {
      final hit = await _cache.read(_serverId, cacheKey);
      if (hit == null) return null;
      final m = jsonDecode(hit.json);
      if (m is! Map) return null;
      final cs = DateTime.tryParse('${m['start']}');
      final ce = DateTime.tryParse('${m['end']}');
      final cachedUnmonitored = m['unmonitored'] == true;
      if (cs == null || ce == null) return null;
      final covers = !start.toUtc().isBefore(cs) && !end.toUtc().isAfter(ce);
      // A window that includes unmonitored episodes can answer both.
      if (!covers || (includeUnmonitored && !cachedUnmonitored)) return null;
      final list = <SonarrEpisode>[];
      for (final item in (m['episodes'] as List?) ?? const []) {
        if (item is! Map) continue;
        try {
          final e = SonarrEpisode.fromJson(item.cast<String, Object?>());
          final airs = e.airs;
          if (airs != null &&
              (airs.isBefore(start.toUtc()) || !airs.isBefore(end.toUtc()))) {
            continue;
          }
          if (!includeUnmonitored && !e.monitored) continue;
          list.add(e);
        } on FormatException {
          // Skip a damaged entry; keep the rest.
        }
      }
      return CalendarSnapshot(episodes: list, fetchedAt: hit.fetchedAt);
    } on Object {
      return null;
    }
  }

  Future<void> _store(
    DateTime start,
    DateTime end,
    bool includeUnmonitored,
    List<SonarrEpisode> items,
    DateTime at,
  ) async {
    try {
      await _cache.write(
        _serverId,
        cacheKey,
        jsonEncode({
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
          'unmonitored': includeUnmonitored,
          'episodes': [for (final e in items) e.toJson()],
        }),
        at,
      );
    } on Object {
      // The cache is best effort.
    }
  }
}
