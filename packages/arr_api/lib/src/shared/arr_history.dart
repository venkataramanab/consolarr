// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/src/arr_client_base.dart';
import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';

/// The `eventType` value of "a download was imported" (`downloadFolderImported`
/// in both Sonarr and Radarr). Sent as a number; answered as a string by most
/// versions and as a number by some.
const _importEventCode = 3;
const _importEventName = 'downloadfolderimported';

/// One import event of `GET /history` (Sonarr and Radarr share the shape).
///
/// Titles are server text: render as plain text only, never log or report
/// them.
class ArrHistoryItem {
  const ArrHistoryItem({
    required this.id,
    this.date,
    this.seriesId,
    this.episodeId,
    this.movieId,
    this.seasonNumber,
    this.episodeNumber,
    this.title,
    this.episodeTitle,
    this.images = const [],
  });

  /// Parses one history record. Throws [FormatException] without an id.
  factory ArrHistoryItem.fromJson(Map<String, Object?> json) {
    final series = JsonRead.map(json['series']);
    final movie = JsonRead.map(json['movie']);
    final episode = JsonRead.map(json['episode']);
    final media = series ?? movie;
    final date = JsonRead.date(json, 'date');
    return ArrHistoryItem(
      id: JsonRead.requiredInt(json, 'id'),
      date: date?.toUtc(),
      seriesId:
          JsonRead.intOrNull(json, 'seriesId') ??
          (series == null ? null : JsonRead.intOrNull(series, 'id')),
      episodeId:
          JsonRead.intOrNull(json, 'episodeId') ??
          (episode == null ? null : JsonRead.intOrNull(episode, 'id')),
      movieId:
          JsonRead.intOrNull(json, 'movieId') ??
          (movie == null ? null : JsonRead.intOrNull(movie, 'id')),
      seasonNumber: episode == null
          ? null
          : JsonRead.intOrNull(episode, 'seasonNumber'),
      episodeNumber: episode == null
          ? null
          : JsonRead.intOrNull(episode, 'episodeNumber'),
      title: media == null ? null : JsonRead.string(media, 'title'),
      episodeTitle: episode == null ? null : JsonRead.string(episode, 'title'),
      images: media == null
          ? const []
          : [
              for (final i in JsonRead.list(media, 'images'))
                if (JsonRead.map(i) case final m?) ArrImage.fromJson(m),
            ],
    );
  }

  final int id;

  /// When the import happened (UTC).
  final DateTime? date;
  final int? seriesId;
  final int? episodeId;
  final int? movieId;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Series or movie title when the server embedded it.
  final String? title;
  final String? episodeTitle;

  /// Artwork of the embedded series or movie (server-relative paths only).
  final List<ArrImage> images;

  @override
  bool operator ==(Object other) =>
      other is ArrHistoryItem &&
      other.id == id &&
      other.date == date &&
      other.seriesId == seriesId &&
      other.episodeId == episodeId &&
      other.movieId == movieId &&
      other.seasonNumber == seasonNumber &&
      other.episodeNumber == episodeNumber &&
      other.title == title &&
      other.episodeTitle == episodeTitle &&
      other.images.length == images.length;

  @override
  int get hashCode => Object.hash(id, date, seriesId, movieId, title);

  @override
  String toString() => 'ArrHistoryItem($id)';
}

/// The history reads both services share.
abstract interface class ArrHistoryApi {
  /// The newest import events, newest first (`GET api/v3/history`), at most
  /// [limit] (1..100).
  Future<Result<List<ArrHistoryItem>>> recentImports({int limit = 20});
}

/// A history record plus whether it is an import (`null`: the server did not
/// say, which is taken as "the filter was applied").
typedef _Row = ({ArrHistoryItem item, bool? isImport});

bool? _isImport(Object? eventType) {
  if (eventType is int) return eventType == _importEventCode;
  if (eventType is String) {
    final text = eventType.toLowerCase();
    if (text == _importEventName) return true;
    final number = int.tryParse(text);
    return number == null ? false : number == _importEventCode;
  }
  return null;
}

_Row _parseRow(Map<String, Object?> json) => (
  item: ArrHistoryItem.fromJson(json),
  isImport: _isImport(json['eventType']),
);

/// A paged `records` envelope (v3, v4) or a bare array. Top level, so only the
/// body is ever sent to another isolate.
ParsedRows<ArrHistoryItem> parseHistoryBody(String body) {
  final decoded = jsonDecode(body);
  final Object? records = decoded is List
      ? decoded
      : JsonRead.map(decoded)?['records'];
  if (records == null) throw const FormatException('expected a history page');
  final rows = parseArrList(records, _parseRow);
  return ParsedRows([
    for (final r in rows.items)
      if (r.isImport ?? true) r.item,
  ], skipped: rows.skipped);
}

/// Adds [ArrHistoryApi] to a client. The client names the `include*` query
/// parameters of its service in [historyIncludes].
mixin ArrHistoryReader on ArrClientBase implements ArrHistoryApi {
  /// Which embedded objects the service can attach (`includeSeries` and
  /// `includeEpisode` for Sonarr, `includeMovie` for Radarr).
  List<String> get historyIncludes;

  @override
  Future<Result<List<ArrHistoryItem>>> recentImports({int limit = 20}) =>
      guard(() async {
        final query = <String, String>{
          'page': '1',
          'pageSize': '${limit.clamp(1, 100)}',
          'sortKey': 'date',
          'sortDirection': 'descending',
          'eventType': '$_importEventCode',
          for (final name in historyIncludes) name: 'true',
        };
        final response = await dio.getUri<String>(
          uri('api/v3/history').replace(queryParameters: query),
          options: Options(responseType: ResponseType.plain),
        );
        final parsed = await decodeOffIsolate(
          runner,
          response.data ?? '',
          parseHistoryBody,
        );
        return parsed.items;
      });
}
