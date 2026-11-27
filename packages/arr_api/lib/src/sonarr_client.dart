// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/src/arr_api.dart';
import 'package:arr_api/src/arr_client_base.dart';
import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/models.dart';
import 'package:arr_api/src/shared/arr_command.dart';
import 'package:arr_api/src/shared/arr_page.dart';
import 'package:arr_api/src/shared/arr_queue.dart';
import 'package:arr_api/src/shared/arr_release.dart';
import 'package:arr_api/src/sonarr/sonarr_episode.dart';
import 'package:arr_api/src/sonarr/sonarr_lookup.dart';
import 'package:arr_api/src/sonarr/sonarr_series_detail.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';

// Parse entry points for [decodeOffIsolate]. Top level, so nothing but the body
// and (static) parser functions is ever sent to another isolate.
ParsedRows<SonarrSeries> _parseSeries(String body) => parseSeriesList(body);

ArrPage<ArrQueueItem> _parseQueuePage(String body) =>
    ArrPage.fromJson(jsonDecode(body), ArrQueueItem.fromJson);

ArrPage<SonarrEpisode> _parseEpisodePage(String body) =>
    ArrPage.fromJson(jsonDecode(body), SonarrEpisode.fromJson);

ParsedRows<SonarrEpisode> _parseEpisodes(String body) =>
    parseArrList(jsonDecode(body), SonarrEpisode.fromJson);

ParsedRows<ArrRelease> _parseReleases(String body) =>
    parseArrList(jsonDecode(body), ArrRelease.fromJson);

ParsedRows<SonarrLookupResult> _parseLookup(String body) =>
    parseArrList(jsonDecode(body), SonarrLookupResult.fromJson);

/// Hand-written, tolerant Sonarr v3 client (also works with v4).
///
/// URL building, artwork URLs and the shared lists (quality profiles, root
/// folders, tags) come from [ArrClientBase].
class SonarrClient extends ArrClientBase implements SonarrApi {
  SonarrClient({required super.dio, super.parseRunner, this.onRowsSkipped});

  /// Called with the number of malformed series rows that were skipped (only
  /// when greater than zero). A count only: never row content.
  final void Function(int skipped)? onRowsSkipped;

  @override
  ServiceKind get kind => ServiceKind.sonarr;

  @override
  Future<Result<ArrSystemStatus>> systemStatus() async {
    try {
      final ArrSystemStatus status;
      try {
        status = parseSystemStatus(await getText('api/v3/system/status'));
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        return await _probeLegacy();
      }
      return _checkVersion(status);
    } on FormatException {
      return const Result.err(AppError(ErrorCategory.parseError));
    } on Object catch (e) {
      return Result.err(appErrorFromDio(e));
    }
  }

  /// Sonarr v2 only has `api/system/status`.
  Future<Result<ArrSystemStatus>> _probeLegacy() async {
    try {
      final legacy = parseSystemStatus(await getText('api/system/status'));
      final major = legacy.majorVersion;
      if (major != null && major < ArrClientBase.minMajorVersion) {
        return const Result.err(AppError(ErrorCategory.unsupportedVersion));
      }
    } on Object {
      // Fall through: the probe is best effort.
    }
    return const Result.err(AppError(ErrorCategory.notFound));
  }

  Result<ArrSystemStatus> _checkVersion(ArrSystemStatus status) {
    final major = status.majorVersion;
    if (major != null && major < ArrClientBase.minMajorVersion) {
      return const Result.err(AppError(ErrorCategory.unsupportedVersion));
    }
    return Result.ok(status);
  }

  @override
  Future<Result<List<SonarrSeries>>> series() => guard(() async {
    final body = await getText('api/v3/series');
    final parsed = await decodeOffIsolate(runner, body, _parseSeries);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Uri? artworkUri(SonarrSeries series, SonarrImageType type) =>
      artworkUriFor(series.images, type);

  // --- helpers ---------------------------------------------------------------

  Uri _uriWith(String path, Map<String, Object?> query) {
    final base = uri(path);
    final q = {
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    return q.isEmpty ? base : base.replace(queryParameters: q);
  }

  /// Sends a request with a JSON body and returns the response text.
  Future<String> _send(String method, Uri target, {Object? body}) async {
    final response = await dio.requestUri<String>(
      target,
      data: body == null ? null : jsonEncode(body),
      options: Options(
        method: method,
        contentType: body == null ? null : Headers.jsonContentType,
        responseType: ResponseType.plain,
      ),
    );
    return response.data ?? '';
  }

  Future<String> _get(
    String path, [
    Map<String, Object?> query = const {},
  ]) async {
    final response = await dio.getUri<String>(
      _uriWith(path, query),
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  Future<Result<List<T>>> _rows<T>(
    String path,
    Map<String, Object?> query,
    ParsedRows<T> Function(String body) parse,
  ) => guard(() async {
    final parsed = await decodeOffIsolate(
      runner,
      await _get(path, query),
      parse,
    );
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  // --- detail and editing ------------------------------------------------------

  @override
  Future<Result<SonarrSeriesDetail>> seriesDetail(int id) => guard(
    () async =>
        SonarrSeriesDetail.fromJson(_object(await _get('api/v3/series/$id'))),
  );

  @override
  Future<Result<SonarrSeriesDetail>> updateSeries(
    int id,
    Map<String, Object?> payload,
  ) => guard(() async {
    final body = await _send(
      'PUT',
      _uriWith('api/v3/series/$id', {'moveFiles': false}),
      body: payload,
    );
    return SonarrSeriesDetail.fromJson(_object(body));
  });

  @override
  Future<Result<List<SonarrEpisode>>> episodes(int seriesId) => _rows(
    'api/v3/episode',
    {'seriesId': seriesId, 'includeEpisodeFile': true},
    _parseEpisodes,
  );

  @override
  Future<Result<void>> setEpisodesMonitored(
    List<int> episodeIds, {
    required bool monitored,
  }) => guard(() async {
    if (episodeIds.isEmpty) return;
    if (!_bulkMonitorMissing) {
      try {
        await _send(
          'PUT',
          uri('api/v3/episode/monitor'),
          body: {'episodeIds': episodeIds, 'monitored': monitored},
        );
        return;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code != 404 && code != 405) rethrow;
        // Remembered for this client (one per server session): do not probe
        // the missing endpoint again.
        _bulkMonitorMissing = true;
      }
    }
    // Older servers: one GET and one PUT per episode. Bounded, so a whole
    // series can never turn into hundreds of requests.
    if (episodeIds.length > maxFallbackEpisodes) {
      throw const AppError(ErrorCategory.requestTooLarge);
    }
    for (final id in episodeIds) {
      final current = _object(await _get('api/v3/episode/$id'));
      await _send(
        'PUT',
        uri('api/v3/episode/$id'),
        body: {...current, 'monitored': monitored},
      );
    }
  });

  /// Most episodes changed one by one on a server without the bulk endpoint.
  static const maxFallbackEpisodes = 50;

  bool _bulkMonitorMissing = false;

  // --- calendar, queue, wanted ---------------------------------------------------

  static String _day(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
  }

  @override
  Future<Result<List<SonarrEpisode>>> calendar({
    required DateTime start,
    required DateTime end,
    bool includeUnmonitored = false,
  }) => _rows('api/v3/calendar', {
    'start': _day(start),
    'end': _day(end),
    'unmonitored': includeUnmonitored,
    'includeSeries': true,
  }, _parseEpisodes);

  /// Most queue pages read in one refresh, and the page size.
  static const _queuePageSize = 200;
  static const _queueMaxPages = 5;

  @override
  Future<Result<List<ArrQueueItem>>> queue() => guard(() async {
    final items = <ArrQueueItem>[];
    for (var page = 1; page <= _queueMaxPages; page++) {
      final body = await _get('api/v3/queue', {
        'page': page,
        'pageSize': _queuePageSize,
        'includeSeries': true,
        'includeEpisode': true,
      });
      final parsed = await decodeOffIsolate(runner, body, _parseQueuePage);
      if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
      items.addAll(parsed.records);
      if (!parsed.hasMore) break;
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
    await _send(
      'DELETE',
      _uriWith('api/v3/queue/$id', {
        'removeFromClient': removeFromClient,
        // `blacklist` is the v3 spelling, `blocklist` the later one.
        'blocklist': block,
        'blacklist': block,
        'skipRedownload': blocklist == ArrBlocklistChoice.blocklistOnly,
      }),
    );
  });

  @override
  Future<Result<ArrPage<SonarrEpisode>>> wanted(
    SonarrWantedKind kind, {
    int page = 1,
    int pageSize = 50,
  }) => guard(() async {
    final body = await _get(
      kind == SonarrWantedKind.missing
          ? 'api/v3/wanted/missing'
          : 'api/v3/wanted/cutoff',
      {
        'page': page,
        'pageSize': pageSize,
        'sortKey': 'airDateUtc',
        'sortDirection': 'descending',
        'includeSeries': true,
        'monitored': true,
      },
    );
    final parsed = await decodeOffIsolate(runner, body, _parseEpisodePage);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed;
  });

  // --- commands and releases -----------------------------------------------------

  @override
  Future<Result<ArrCommand>> startCommand(ArrCommandRequest request) =>
      guard(() async {
        final body = await _send(
          'POST',
          uri('api/v3/command'),
          body: request.toJson(),
        );
        return ArrCommand.fromJson(_object(body));
      });

  @override
  Future<Result<ArrCommand>> command(int id) => guard(
    () async => ArrCommand.fromJson(_object(await _get('api/v3/command/$id'))),
  );

  @override
  Future<Result<List<ArrRelease>>> releases({
    int? episodeId,
    int? seriesId,
    int? seasonNumber,
  }) => _rows(
    'api/v3/release',
    episodeId != null
        ? {'episodeId': episodeId}
        : {'seriesId': seriesId, 'seasonNumber': seasonNumber},
    _parseReleases,
  );

  @override
  Future<Result<void>> grabRelease(ArrRelease release) => guard(() async {
    await _send(
      'POST',
      uri('api/v3/release'),
      body: {'guid': release.guid, 'indexerId': release.indexerId},
    );
  });

  // --- lookup and add ------------------------------------------------------------

  @override
  Future<Result<List<SonarrLookupResult>>> lookup(String term) =>
      _rows('api/v3/series/lookup', {'term': term}, _parseLookup);

  @override
  Future<Result<SonarrSeriesDetail>> addSeries(
    SonarrLookupResult lookup,
    SonarrAddOptions options,
  ) => guard(() async {
    final payload = Map<String, Object?>.of(lookup.raw)
      ..remove('id')
      ..['qualityProfileId'] = options.qualityProfileId
      ..['rootFolderPath'] = options.rootFolderPath
      ..['seriesType'] = options.seriesType.name
      ..['seasonFolder'] = options.seasonFolder
      ..['monitored'] = options.monitored
      ..['tags'] = options.tags
      ..['addOptions'] = {
        'monitor': options.monitor.name,
        'searchForMissingEpisodes': options.searchForMissing,
        'searchForCutoffUnmetEpisodes': false,
      };
    // Sonarr v3 requires a language profile; v4 removed the endpoint.
    final languageProfileId = await _languageProfileId();
    if (languageProfileId != null) {
      payload['languageProfileId'] = languageProfileId;
    }
    final body = await _send('POST', uri('api/v3/series'), body: payload);
    return SonarrSeriesDetail.fromJson(_object(body));
  });

  Future<int?> _languageProfileId() async {
    try {
      final decoded = jsonDecode(await _get('api/v3/languageprofile'));
      if (decoded is! List) return null;
      for (final e in decoded) {
        final id = JsonRead.map(e)?['id'];
        if (id is int) return id;
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404 || code == 405) return null;
      rethrow;
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  Future<Result<ArrTag>> createTag(String label) => guard(() async {
    final body = await _send('POST', uri('api/v3/tag'), body: {'label': label});
    return ArrTag.fromJson(_object(body));
  });

  Map<String, Object?> _object(String body) =>
      JsonRead.map(jsonDecode(body)) ??
      (throw const FormatException('expected an object'));
}
