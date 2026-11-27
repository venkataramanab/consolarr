// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/src/arr_api.dart';
import 'package:arr_api/src/arr_client_base.dart';
import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/models.dart';
import 'package:arr_api/src/radarr/radarr_models.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';

ParsedRows<RadarrMovie> _parseMovies(String body) => parseMovieList(body);

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
    final parsed = body.length > ArrClientBase.isolateThresholdBytes
        ? await runner(() => _parseMovies(body))
        : parseMovieList(body);
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
    final body = response.data ?? '';
    // An empty lookup is an empty array, not an error.
    final decoded = jsonDecode(body);
    if (decoded is List && decoded.isEmpty) return <RadarrMovie>[];
    return _movieRows(body);
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
  Future<Result<List<RadarrQueueItem>>> queue() => guard(() async {
    final response = await dio.getUri<String>(
      uri('api/v3/queue').replace(
        queryParameters: {
          'page': '1',
          'pageSize': '200',
          'includeMovie': 'false',
        },
      ),
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data ?? '';
    final decoded = jsonDecode(body);
    final records = decoded is Map ? decoded['records'] : decoded;
    if (records is List && records.isEmpty) return <RadarrQueueItem>[];
    final parsed = parseQueue(body);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required QueueBlocklist blocklist,
  }) => guard(() async {
    await dio.deleteUri<void>(
      uri('api/v3/queue/$id').replace(
        queryParameters: {
          'removeFromClient': '$removeFromClient',
          'blocklist': '${blocklist != QueueBlocklist.none}',
          'skipRedownload': '${blocklist != QueueBlocklist.blocklistAndSearch}',
        },
      ),
    );
  });

  Future<RadarrCommand> _postCommand(Map<String, Object?> body) async {
    final response = await dio.postUri<String>(
      uri('api/v3/command'),
      data: jsonEncode(body),
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
      ),
    );
    final m = JsonRead.map(jsonDecode(response.data ?? ''));
    if (m == null) throw const FormatException('expected an object');
    return RadarrCommand.fromJson(m);
  }

  @override
  Future<Result<RadarrCommand>> searchMovies(List<int> movieIds) =>
      guard(() => _postCommand({'name': 'MoviesSearch', 'movieIds': movieIds}));

  @override
  Future<Result<RadarrCommand>> searchAllMissing() =>
      guard(() => _postCommand({'name': 'MissingMoviesSearch'}));

  @override
  Future<Result<RadarrCommand>> command(int id) => guard(() async {
    final m = JsonRead.map(jsonDecode(await getText('api/v3/command/$id')));
    if (m == null) throw const FormatException('expected an object');
    return RadarrCommand.fromJson(m);
  });

  @override
  Future<Result<List<RadarrRelease>>> releases(int movieId) => guard(() async {
    final response = await dio.getUri<String>(
      uri('api/v3/release').replace(queryParameters: {'movieId': '$movieId'}),
      options: Options(
        responseType: ResponseType.plain,
        // Indexer searches are slow.
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    final body = response.data ?? '';
    final decoded = jsonDecode(body);
    if (decoded is List && decoded.isEmpty) return <RadarrRelease>[];
    final parsed = body.length > ArrClientBase.isolateThresholdBytes
        ? await runner(() => parseReleases(body))
        : parseReleases(body);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Future<Result<void>> grab(RadarrRelease release) => guard(() async {
    await dio.postUri<void>(
      uri('api/v3/release'),
      data: jsonEncode({'guid': release.guid, 'indexerId': release.indexerId}),
      options: Options(contentType: Headers.jsonContentType),
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
