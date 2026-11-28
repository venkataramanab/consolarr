// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:core/core.dart';

/// A value at a point in time. With [offlineError] set it is the last cached
/// copy (fetched at [fetchedAt]) and the live refresh failed with that error.
class Snapshot<T> {
  const Snapshot({
    required this.value,
    required this.fetchedAt,
    this.offlineError,
  });

  final T value;
  final DateTime fetchedAt;
  final AppError? offlineError;

  bool get isOffline => offlineError != null;

  Snapshot<T> withOfflineError(AppError error) =>
      Snapshot(value: value, fetchedAt: fetchedAt, offlineError: error);
}

/// Loads Radarr data and keeps the last good copy of the library, each movie
/// and the calendar for the offline view (RAD-22).
///
/// Only the categories in `kOfflineFallbackCategories` fall back to cache;
/// `auth_failed`, `unsupported_version` and TLS errors are returned as they
/// are and never served from (or written to) the cache.
class RadarrRepository {
  RadarrRepository({
    required this.api,
    required PayloadCache cache,
    required String serverId,
    required DateTime Function() clock,
  }) : _cache = cache,
       _serverId = serverId,
       _clock = clock;

  static const libraryKey = 'radarr.movies';
  static const calendarKey = 'radarr.calendar';
  static String movieKey(int id) => 'radarr.movie.$id';

  final RadarrApi api;
  final PayloadCache _cache;
  final String _serverId;
  final DateTime Function() _clock;

  Future<Result<Snapshot<T>>> _load<T>({
    required Future<Result<T>> Function() live,
    required String key,
    required Object? Function(T value) encode,
    required T? Function(Object? json) decode,
  }) async {
    final result = await live();
    final value = result.valueOrNull;
    if (result.isOk && value != null) {
      final at = _clock();
      try {
        await _cache.write(_serverId, key, jsonEncode(encode(value)), at);
      } on Object {
        // Best effort.
      }
      return Result.ok(Snapshot(value: value, fetchedAt: at));
    }
    final error = result.errorOrNull!;
    if (kOfflineFallbackCategories.contains(error.category)) {
      final copy = await _cached(key, decode);
      if (copy != null) return Result.ok(copy.withOfflineError(error));
    }
    return Result.err(error);
  }

  Future<Snapshot<T>?> _cached<T>(
    String key,
    T? Function(Object? json) decode,
  ) async {
    try {
      final hit = await _cache.read(_serverId, key);
      if (hit == null) return null;
      final value = decode(jsonDecode(hit.json));
      return value == null
          ? null
          : Snapshot(value: value, fetchedAt: hit.fetchedAt);
    } on Object {
      return null;
    }
  }

  static List<RadarrMovie>? _decodeMovies(Object? json) {
    if (json is! List) return null;
    final out = <RadarrMovie>[];
    for (final item in json) {
      if (item is! Map) continue;
      try {
        out.add(RadarrMovie.fromJson(item.cast<String, Object?>()));
      } on FormatException {
        // Skip a damaged entry.
      }
    }
    return out;
  }

  static Object? _encodeMovies(List<RadarrMovie> m) => [
    for (final x in m) x.toJson(),
  ];

  /// The library: live, else the cached copy for reachability failures.
  Future<Result<Snapshot<List<RadarrMovie>>>> library() => _load(
    live: api.movies,
    key: libraryKey,
    encode: _encodeMovies,
    decode: _decodeMovies,
  );

  /// One movie. Offline it falls back to its own cached copy, then to its row
  /// in the cached library.
  Future<Result<Snapshot<RadarrMovie>>> movie(int id) async {
    final result = await _load<RadarrMovie>(
      live: () async {
        final live = await api.movie(id);
        // Deleted on the server: nothing may bring it back from the cache
        // (`not_found` is an offline-fallback category, so this has to happen
        // before the fallback is looked up).
        if (live.errorOrNull?.category == ErrorCategory.notFound) {
          await _forget(id);
        }
        return live;
      },
      key: movieKey(id),
      encode: (m) => m.toJson(),
      decode: (j) =>
          j is Map ? RadarrMovie.fromJson(j.cast<String, Object?>()) : null,
    );
    final error = result.errorOrNull;
    if (error != null && kOfflineFallbackCategories.contains(error.category)) {
      final lib = await _cached(libraryKey, _decodeMovies);
      if (lib != null) {
        for (final m in lib.value) {
          if (m.id == id) {
            return Result.ok(
              Snapshot(value: m, fetchedAt: lib.fetchedAt, offlineError: error),
            );
          }
        }
      }
    }
    return result;
  }

  /// Drops the cached copy of movie [id] and its row in the cached library, so
  /// an offline fallback cannot resurrect a movie the server no longer has.
  Future<void> _forget(int id) async {
    try {
      // The cache interface has no per-key delete; an empty value decodes to
      // "nothing cached" and is replaced by the next successful load.
      await _cache.write(_serverId, movieKey(id), 'null', _clock());
      final lib = await _cached(libraryKey, _decodeMovies);
      if (lib == null || !lib.value.any((m) => m.id == id)) return;
      await _cache.write(
        _serverId,
        libraryKey,
        jsonEncode(
          _encodeMovies([
            for (final m in lib.value)
              if (m.id != id) m,
          ]),
        ),
        lib.fetchedAt,
      );
    } on Object {
      // Best effort.
    }
  }

  /// Movies with a release date in the range.
  Future<Result<Snapshot<List<RadarrMovie>>>> calendar(
    DateTime start,
    DateTime end,
  ) => _load(
    live: () => api.calendar(start, end),
    key: calendarKey,
    encode: _encodeMovies,
    decode: _decodeMovies,
  );

  /// Drops the cached copy of a movie that was deleted on the server.
  Future<Snapshot<List<RadarrMovie>>?> cachedLibrary() =>
      _cached(libraryKey, _decodeMovies);
}
