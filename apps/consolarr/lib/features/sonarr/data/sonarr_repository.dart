// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:core/core.dart';

/// The series list at a point in time.
///
/// When [offlineError] is set the list is the last cached copy (fetched at
/// [fetchedAt]) and the live refresh failed with that error.
class SeriesSnapshot {
  const SeriesSnapshot({
    required this.series,
    required this.fetchedAt,
    this.offlineError,
  });

  final List<SonarrSeries> series;
  final DateTime fetchedAt;
  final AppError? offlineError;

  SeriesSnapshot withOfflineError(AppError error) =>
      SeriesSnapshot(series: series, fetchedAt: fetchedAt, offlineError: error);
}

/// Loads the Sonarr series list and keeps the last good copy for the offline
/// view.
class SonarrRepository {
  SonarrRepository({
    required SonarrApi api,
    required PayloadCache cache,
    required String serverId,
    required DateTime Function() clock,
  }) : _api = api,
       _cache = cache,
       _serverId = serverId,
       _clock = clock;

  /// Payload cache key for the series list.
  static const cacheKey = 'sonarr.series';

  /// Failures after which the cached copy is shown (the server is not
  /// reachable or not healthy). Auth and version problems are shown as such,
  /// never hidden behind old data; a pin mismatch must block.
  static const _offlineFallback = {
    ErrorCategory.networkUnreachable,
    ErrorCategory.timeout,
    ErrorCategory.serverError,
    ErrorCategory.notFound,
    ErrorCategory.parseError,
    ErrorCategory.responseTooLarge,
  };

  final SonarrApi _api;
  final PayloadCache _cache;
  final String _serverId;
  final DateTime Function() _clock;

  /// Fetches the live list; on a reachability failure returns the cached copy
  /// with the error attached, or the error when nothing is cached.
  Future<Result<SeriesSnapshot>> load() async {
    final live = await _api.series();
    if (live.isOk) {
      final list = live.valueOrNull!;
      final at = _clock();
      await _store(list, at);
      return Result.ok(SeriesSnapshot(series: list, fetchedAt: at));
    }
    var error = live.errorOrNull!;
    if (error.category == ErrorCategory.notFound) {
      // Sonarr v2 has no /api/v3: tell "too old" apart from "wrong path".
      final status = await _api.systemStatus();
      final statusError = status.errorOrNull;
      if (statusError?.category == ErrorCategory.unsupportedVersion) {
        error = statusError!;
      }
    }
    if (_offlineFallback.contains(error.category)) {
      final copy = await cached();
      if (copy != null) return Result.ok(copy.withOfflineError(error));
    }
    return Result.err(error);
  }

  /// The cached copy without any network access, or null.
  Future<SeriesSnapshot?> cached() async {
    try {
      final hit = await _cache.read(_serverId, cacheKey);
      if (hit == null) return null;
      final decoded = jsonDecode(hit.json);
      if (decoded is! List) return null;
      final list = <SonarrSeries>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          list.add(SonarrSeries.fromJson(item.cast<String, Object?>()));
        } on FormatException {
          // Skip a damaged entry; keep the rest.
        }
      }
      return SeriesSnapshot(series: list, fetchedAt: hit.fetchedAt);
    } on Object {
      return null;
    }
  }

  Future<void> _store(List<SonarrSeries> list, DateTime at) async {
    try {
      await _cache.write(
        _serverId,
        cacheKey,
        jsonEncode([for (final s in list) s.toJson()]),
        at,
      );
    } on Object {
      // The cache is best effort; a failed write must not fail the refresh.
    }
  }
}
