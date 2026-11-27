// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:core/core.dart';

/// Series lifecycle as reported by Sonarr.
enum SeriesStatus { continuing, ended, upcoming, deleted, unknown }

/// Sonarr series type.
enum SeriesType { standard, daily, anime, unknown }

/// Artwork kinds the app uses (shared with Radarr, see `ArrImageType`).
typedef SonarrImageType = ArrImageType;

/// One artwork reference (shared with Radarr, see `ArrImage`).
typedef SonarrImage = ArrImage;

SeriesStatus _status(String? v) => SeriesStatus.values.firstWhere(
  (e) => e.name == v,
  orElse: () => SeriesStatus.unknown,
);

SeriesType _seriesType(String? v) => SeriesType.values.firstWhere(
  (e) => e.name == v,
  orElse: () => SeriesType.unknown,
);

/// The subset of `/system/status` the app needs.
class ArrSystemStatus {
  const ArrSystemStatus({required this.version, this.appName});

  /// Server version, e.g. `4.0.9.2244`. Drives version-gated behaviour.
  final String version;

  /// `appName` from the status payload when present.
  final String? appName;

  /// Leading numeric component of [version], or null when unparsable.
  int? get majorVersion => int.tryParse(version.split('.').first);
}

/// Episode and size statistics of a series.
class SeriesStatistics {
  const SeriesStatistics({
    this.seasonCount = 0,
    this.episodeFileCount = 0,
    this.episodeCount = 0,
    this.totalEpisodeCount = 0,
    this.sizeOnDisk = 0,
    this.percentOfEpisodes = 0,
  });

  factory SeriesStatistics.fromJson(Map<String, Object?> json) =>
      SeriesStatistics(
        seasonCount: JsonRead.integer(json, 'seasonCount'),
        episodeFileCount: JsonRead.integer(json, 'episodeFileCount'),
        episodeCount: JsonRead.integer(json, 'episodeCount'),
        totalEpisodeCount: JsonRead.integer(json, 'totalEpisodeCount'),
        sizeOnDisk: JsonRead.integer(json, 'sizeOnDisk'),
        percentOfEpisodes: JsonRead.decimal(json, 'percentOfEpisodes'),
      );

  final int seasonCount;
  final int episodeFileCount;
  final int episodeCount;
  final int totalEpisodeCount;

  /// Bytes.
  final int sizeOnDisk;

  /// 0..100.
  final double percentOfEpisodes;

  Map<String, Object?> toJson() => {
    'seasonCount': seasonCount,
    'episodeFileCount': episodeFileCount,
    'episodeCount': episodeCount,
    'totalEpisodeCount': totalEpisodeCount,
    'sizeOnDisk': sizeOnDisk,
    'percentOfEpisodes': percentOfEpisodes,
  };

  @override
  bool operator ==(Object other) =>
      other is SeriesStatistics &&
      other.seasonCount == seasonCount &&
      other.episodeFileCount == episodeFileCount &&
      other.episodeCount == episodeCount &&
      other.totalEpisodeCount == totalEpisodeCount &&
      other.sizeOnDisk == sizeOnDisk &&
      other.percentOfEpisodes == percentOfEpisodes;

  @override
  int get hashCode => Object.hash(
    seasonCount,
    episodeFileCount,
    episodeCount,
    totalEpisodeCount,
    sizeOnDisk,
    percentOfEpisodes,
  );
}

/// A Sonarr series (v3 API, tolerant of v4).
///
/// Server-supplied strings are plain text; never interpret them as markup.
class SonarrSeries {
  const SonarrSeries({
    required this.id,
    required this.title,
    required this.sortTitle,
    this.year,
    this.status = SeriesStatus.unknown,
    this.monitored = false,
    this.network,
    this.seriesType = SeriesType.unknown,
    this.nextAiring,
    this.added,
    this.qualityProfileId,
    this.tags = const [],
    this.images = const [],
    this.statistics = const SeriesStatistics(),
  });

  /// Throws [FormatException] when `id` or `title` is missing or mistyped.
  /// Everything else is optional and tolerated when absent or mistyped.
  factory SonarrSeries.fromJson(Map<String, Object?> json) {
    final title = JsonRead.requiredString(json, 'title');
    final year = JsonRead.intOrNull(json, 'year');
    final stats = JsonRead.map(json['statistics']);
    return SonarrSeries(
      id: JsonRead.requiredInt(json, 'id'),
      title: title,
      sortTitle: JsonRead.string(json, 'sortTitle') ?? title,
      year: year != null && year > 0 ? year : null,
      status: _status(JsonRead.string(json, 'status')),
      monitored: JsonRead.boolean(json, 'monitored'),
      network: JsonRead.string(json, 'network'),
      seriesType: _seriesType(JsonRead.string(json, 'seriesType')),
      nextAiring: JsonRead.date(json, 'nextAiring'),
      added: JsonRead.date(json, 'added'),
      qualityProfileId: JsonRead.intOrNull(json, 'qualityProfileId'),
      tags: [
        for (final t in JsonRead.list(json, 'tags'))
          if (t is int) t,
      ],
      images: [
        for (final i in JsonRead.list(json, 'images'))
          if (JsonRead.map(i) case final m?) SonarrImage.fromJson(m),
      ],
      statistics: stats == null
          ? const SeriesStatistics()
          : SeriesStatistics.fromJson(stats),
    );
  }

  final int id;
  final String title;
  final String sortTitle;
  final int? year;
  final SeriesStatus status;
  final bool monitored;
  final String? network;
  final SeriesType seriesType;
  final DateTime? nextAiring;
  final DateTime? added;
  final int? qualityProfileId;
  final List<int> tags;
  final List<SonarrImage> images;
  final SeriesStatistics statistics;

  /// Cache format; parsed back by [SonarrSeries.fromJson].
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'sortTitle': sortTitle,
    'year': year,
    'status': status.name,
    'monitored': monitored,
    'network': network,
    'seriesType': seriesType.name,
    'nextAiring': nextAiring?.toUtc().toIso8601String(),
    'added': added?.toUtc().toIso8601String(),
    'qualityProfileId': qualityProfileId,
    'tags': tags,
    'images': [for (final i in images) i.toJson()],
    'statistics': statistics.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SonarrSeries &&
      other.id == id &&
      other.title == title &&
      other.sortTitle == sortTitle &&
      other.year == year &&
      other.status == status &&
      other.monitored == monitored &&
      other.network == network &&
      other.seriesType == seriesType &&
      other.nextAiring == nextAiring &&
      other.added == added &&
      other.qualityProfileId == qualityProfileId &&
      _listEq(other.tags, tags) &&
      _listEq(other.images, images) &&
      other.statistics == statistics;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    sortTitle,
    year,
    status,
    monitored,
    network,
    seriesType,
    nextAiring,
    added,
    qualityProfileId,
    Object.hashAll(tags),
    Object.hashAll(images),
    statistics,
  );

  /// Omits the title so logs never carry media titles.
  @override
  String toString() => 'SonarrSeries($id)';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Parses a `GET /series` body. Throws [FormatException] on malformed JSON, a
/// non-array body, or when no element at all could be parsed. Individual
/// malformed elements are skipped and counted ([ParsedRows.skipped]), so one
/// bad row never hides the library. Top level so it can run in an isolate.
ParsedRows<SonarrSeries> parseSeriesList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) throw const FormatException('expected a JSON array');
  return parseRowsTolerant(
    decoded,
    (e) => SonarrSeries.fromJson(
      JsonRead.map(e) ?? (throw const FormatException('expected an object')),
    ),
  );
}

/// Parses a `GET /system/status` body. Throws [FormatException] when the body
/// is not an object with a string `version`.
ArrSystemStatus parseSystemStatus(String body) {
  final m = JsonRead.map(jsonDecode(body));
  if (m == null) throw const FormatException('expected an object');
  return ArrSystemStatus(
    version: JsonRead.requiredString(m, 'version'),
    appName: JsonRead.string(m, 'appName'),
  );
}
