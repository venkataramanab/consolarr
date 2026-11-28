// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/src/arr_api.dart';
import 'package:arr_api/src/arr_client_base.dart';
import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/models.dart';
import 'package:arr_api/src/radarr/radarr_models.dart';
import 'package:arr_api/src/shared/arr_command.dart';
import 'package:arr_api/src/shared/arr_page.dart';
import 'package:arr_api/src/shared/arr_queue.dart';
import 'package:arr_api/src/shared/arr_release.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';

// Parse entry points for [decodeOffIsolate]. Top level, so nothing but the body
// and (static) parser functions is ever sent to another isolate.
ParsedRows<RadarrMovie> _parseMovies(String body) => parseMovieList(body);

ParsedRows<ArrRelease> _parseReleases(String body) =>
    parseArrList(jsonDecode(body), ArrRelease.fromJson);

/// A paged `records` envelope, or (older servers) a bare array.
ArrPage<ArrQueueItem> _parseQueuePage(String body) {
  final decoded = jsonDecode(body);
  if (decoded is List) {
    final rows = parseArrList(decoded, ArrQueueItem.fromJson);
    return ArrPage(
      records: rows.items,
      totalRecords: rows.items.length,
      skipped: rows.skipped,
    );
  }
  return ArrPage.fromJson(decoded, ArrQueueItem.fromJson);
}

/// A grab can take a while on the server (indexer, download client).
const _grabTimeout = Duration(seconds: 90);

/// Indexer searches are slow.
const _releaseTimeout = Duration(seconds: 90);

/// Most queue pages read in one refresh, and the page size.
const _queuePageSize = 200;
const _queueMaxPages = 5;

/// Hand-written, tolerant Radarr v3 client.
class RadarrClient extends ArrClientBase implements RadarrApi {
  RadarrClient({required super.dio, super.parseRunner, this.onRowsSkipped});

  /// Called with the number of malformed rows skipped (only when > 0). A
  /// count only: never row content.
  final void Function(int skipped)? onRowsSkipped;

  @override
  ServiceKind get kind => ServiceKind.radarr;

  @override
  Future<Result<ArrSystemStatus>> systemStatus() => guard(() async {
    final ArrSystemStatus status;
    try {
      status = parseSystemStatus(await getText('api/v3/system/status'));
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      // Radarr v0.2 only has `api/system/status`: tell "too old" apart from a
      // wrong address or path prefix.
      if (await _isLegacy()) throw const _Unsupported();
      rethrow;
    }
    final major = status.majorVersion;
    if (major != null && major < ArrClientBase.minMajorVersion) {
      throw const _Unsupported();
    }
    return status;
  });

  @override
  Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Result.ok(await body());
    } on _Unsupported {
      return const Result.err(AppError(ErrorCategory.unsupportedVersion));
    } on _Invalid {
      return Result.err(invalidRequest());
    } on FormatException {
      return const Result.err(AppError(ErrorCategory.parseError));
    } on Object catch (e) {
      return Result.err(appErrorFromDio(e));
    }
  }

  Future<bool> _isLegacy() async {
    try {
      final legacy = parseSystemStatus(await getText('api/system/status'));
      final major = legacy.majorVersion;
      return major != null && major < ArrClientBase.minMajorVersion;
    } on Object {
      return false;
    }
  }

  Future<List<RadarrMovie>> _movieRows(String body) async {
    final parsed = await decodeOffIsolate(runner, body, _parseMovies);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  }

  @override
  Future<Result<List<RadarrMovie>>> movies() =>
      guard(() async => _movieRows(await getText('api/v3/movie')));

  @override
  Future<Result<RadarrMovie>> movie(int id) =>
      guard(() async => parseMovie(await getText('api/v3/movie/$id')));

  @override
  Future<Result<List<RadarrMovie>>> calendar(DateTime start, DateTime end) =>
      guard(() async {
        final response = await dio.getUri<String>(
          uri('api/v3/calendar').replace(
            queryParameters: {
              'start': start.toUtc().toIso8601String(),
              'end': end.toUtc().toIso8601String(),
              'unmonitored': 'true',
            },
          ),
          options: Options(responseType: ResponseType.plain),
        );
        return _movieRows(response.data ?? '');
      });

  Future<Map<String, Object?>> _rawMovie(int id) async {
    final m = JsonRead.map(jsonDecode(await getText('api/v3/movie/$id')));
    if (m == null) throw const FormatException('expected an object');
    return m;
  }

  @override
  Future<Result<RadarrMovie>> updateMovie(
    int id, {
    bool? monitored,
    int? qualityProfileId,
    MinimumAvailability? minimumAvailability,
    List<int>? tags,
  }) => guard(() async {
    final body = await _rawMovie(id);
    if (monitored != null) body['monitored'] = monitored;
    if (qualityProfileId != null) body['qualityProfileId'] = qualityProfileId;
    if (minimumAvailability != null &&
        minimumAvailability != MinimumAvailability.unknown) {
      body['minimumAvailability'] = minimumAvailability.name;
    }
    if (tags != null) body['tags'] = tags;
    final response = await dio.putUri<String>(
      uri('api/v3/movie/$id'),
      data: jsonEncode(body),
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
      ),
    );
    final text = response.data ?? '';
    return text.isEmpty ? RadarrMovie.fromJson(body) : parseMovie(text);
  });

  @override
  Future<Result<List<RadarrMovie>>> lookup(String term) => guard(() async {
    final response = await dio.getUri<String>(
      uri('api/v3/movie/lookup').replace(queryParameters: {'term': term}),
      options: Options(responseType: ResponseType.plain),
    );
    return _movieRows(response.data ?? '');
  });

  @override
  Future<Result<RadarrMovie>> addMovie(AddMovieRequest request) =>
      guard(() async {
        final movie = request.lookup;
        final tmdbId = movie.tmdbId;
        if (tmdbId == null || movie.inLibrary) throw const _Invalid();
        final body = {
          'title': movie.title,
          'tmdbId': tmdbId,
          'year': ?movie.year,
          'qualityProfileId': request.qualityProfileId,
          'rootFolderPath': request.rootFolderPath,
          'minimumAvailability': request.minimumAvailability.name,
          'monitored': request.monitored,
          'tags': request.tags,
          'images': [for (final i in movie.images) i.toJson()],
          'addOptions': {
            'searchForMovie': request.searchForMovie,
            'monitor': request.addCollection && movie.collectionTitle != null
                ? 'movieAndCollection'
                : 'movieOnly',
          },
        };
        final response = await dio.postUri<String>(
          uri('api/v3/movie'),
          data: jsonEncode(body),
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.jsonContentType,
          ),
        );
        return parseMovie(response.data ?? '');
      });

  @override
  Future<Result<List<ArrQueueItem>>> queue() => guard(() async {
    final items = <ArrQueueItem>[];
    for (var page = 1; page <= _queueMaxPages; page++) {
      final response = await dio.getUri<String>(
        uri('api/v3/queue').replace(
          queryParameters: {
            'page': '$page',
            'pageSize': '$_queuePageSize',
            'includeMovie': 'false',
            // Items whose movie is not in the library (yet) still show up.
            'includeUnknownMovieItems': 'true',
          },
        ),
        options: Options(responseType: ResponseType.plain),
      );
      final parsed = await decodeOffIsolate(
        runner,
        response.data ?? '',
        _parseQueuePage,
      );
      if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
      items.addAll(parsed.records);
      if (!parsed.hasMore || items.length >= parsed.totalRecords) break;
    }
    return items;
  });

  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) => guard(() async {
    final block = blocklist != ArrBlocklistChoice.none;
    await dio.deleteUri<void>(
      uri('api/v3/queue/$id').replace(
        queryParameters: {
          'removeFromClient': '$removeFromClient',
          // `blacklist` is the v3 spelling, `blocklist` the later one.
          'blocklist': '$block',
          'blacklist': '$block',
          'skipRedownload': '${blocklist == ArrBlocklistChoice.blocklistOnly}',
        },
      ),
    );
  });

  Future<ArrCommand> _postCommand(ArrCommandRequest request) async {
    final response = await dio.postUri<String>(
      uri('api/v3/command'),
      data: jsonEncode(request.toJson()),
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
      ),
    );
    final m = JsonRead.map(jsonDecode(response.data ?? ''));
    if (m == null) throw const FormatException('expected an object');
    return ArrCommand.fromJson(m);
  }

  @override
  Future<Result<ArrCommand>> searchMovies(List<int> movieIds) => guard(
    () =>
        _postCommand(ArrCommandRequest('MoviesSearch', {'movieIds': movieIds})),
  );

  @override
  Future<Result<ArrCommand>> searchAllMissing() => guard(
    () => _postCommand(
      // Explicit: some versions search every movie without a filter.
      const ArrCommandRequest('MissingMoviesSearch', {
        'filterKey': 'monitored',
        'filterValue': 'true',
      }),
    ),
  );

  @override
  Future<Result<ArrCommand>> command(int id) => guard(() async {
    final m = JsonRead.map(jsonDecode(await getText('api/v3/command/$id')));
    if (m == null) throw const FormatException('expected an object');
    return ArrCommand.fromJson(m);
  });

  @override
  Future<Result<List<ArrRelease>>> releases(int movieId) => guard(() async {
    final response = await dio.getUri<String>(
      uri('api/v3/release').replace(queryParameters: {'movieId': '$movieId'}),
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: _releaseTimeout,
      ),
    );
    final parsed = await decodeOffIsolate(
      runner,
      response.data ?? '',
      _parseReleases,
    );
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Future<Result<void>> grab(ArrRelease release) => guard(() async {
    await dio.postUri<void>(
      uri('api/v3/release'),
      data: jsonEncode({'guid': release.guid, 'indexerId': release.indexerId}),
      options: Options(
        contentType: Headers.jsonContentType,
        receiveTimeout: _grabTimeout,
      ),
    );
  });

  @override
  Uri? artworkUri(RadarrMovie movie, ArrImageType type) =>
      artworkUriFor(movie.images, type);
}

class _Unsupported implements Exception {
  const _Unsupported();
}

class _Invalid implements Exception {
  const _Invalid();
}
