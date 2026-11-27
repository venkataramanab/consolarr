// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/models.dart';

/// The file of an episode on disk (`episodeFile`).
class SonarrEpisodeFile {
  const SonarrEpisodeFile({required this.id, this.size = 0, this.qualityName});

  factory SonarrEpisodeFile.fromJson(Map<String, Object?> json) {
    final quality = JsonRead.map(JsonRead.map(json['quality'])?['quality']);
    return SonarrEpisodeFile(
      id: JsonRead.integer(json, 'id'),
      size: JsonRead.integer(json, 'size'),
      qualityName: quality == null ? null : JsonRead.string(quality, 'name'),
    );
  }

  final int id;

  /// Bytes.
  final int size;
  final String? qualityName;

  Map<String, Object?> toJson() => {
    'id': id,
    'size': size,
    'quality': {
      'quality': {'name': qualityName},
    },
  };
}

/// One episode (`/episode`, `/calendar`, `/wanted/*`). With `includeSeries`
/// the owning [series] summary is present (calendar, wanted).
class SonarrEpisode {
  const SonarrEpisode({
    required this.id,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.airDateUtc,
    this.airDate,
    this.overview,
    this.hasFile = false,
    this.monitored = false,
    this.runtime,
    this.finaleType,
    this.file,
    this.series,
  });

  factory SonarrEpisode.fromJson(Map<String, Object?> json) {
    final file = JsonRead.map(json['episodeFile']);
    final series = JsonRead.map(json['series']);
    SonarrSeries? parsedSeries;
    if (series != null) {
      try {
        parsedSeries = SonarrSeries.fromJson(series);
      } on FormatException {
        parsedSeries = null;
      }
    }
    return SonarrEpisode(
      id: JsonRead.requiredInt(json, 'id'),
      seriesId: JsonRead.intOrNull(json, 'seriesId') ?? parsedSeries?.id ?? 0,
      seasonNumber: JsonRead.integer(json, 'seasonNumber'),
      episodeNumber: JsonRead.integer(json, 'episodeNumber'),
      title: JsonRead.string(json, 'title'),
      airDateUtc: JsonRead.date(json, 'airDateUtc'),
      airDate: JsonRead.string(json, 'airDate'),
      overview: JsonRead.string(json, 'overview'),
      hasFile:
          JsonRead.boolean(json, 'hasFile') ||
          (file != null && JsonRead.integer(file, 'id') > 0),
      monitored: JsonRead.boolean(json, 'monitored'),
      runtime: JsonRead.intOrNull(json, 'runtime'),
      finaleType: JsonRead.string(json, 'finaleType'),
      file: file == null ? null : SonarrEpisodeFile.fromJson(file),
      series: parsedSeries,
    );
  }

  final int id;
  final int seriesId;
  final int seasonNumber;
  final int episodeNumber;
  final String? title;

  /// When the episode airs (UTC), when the server knows.
  final DateTime? airDateUtc;

  /// `yyyy-MM-dd` as reported (v3 calendar days without a time).
  final String? airDate;
  final String? overview;
  final bool hasFile;
  final bool monitored;
  final int? runtime;
  final String? finaleType;
  final SonarrEpisodeFile? file;
  final SonarrSeries? series;

  /// The air moment: [airDateUtc], else midnight UTC of [airDate].
  DateTime? get airs =>
      airDateUtc ?? (airDate == null ? null : DateTime.tryParse(airDate!));

  SonarrEpisode copyWith({bool? monitored}) => SonarrEpisode(
    id: id,
    seriesId: seriesId,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    title: title,
    airDateUtc: airDateUtc,
    airDate: airDate,
    overview: overview,
    hasFile: hasFile,
    monitored: monitored ?? this.monitored,
    runtime: runtime,
    finaleType: finaleType,
    file: file,
    series: series,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'seriesId': seriesId,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'title': title,
    'airDateUtc': airDateUtc?.toUtc().toIso8601String(),
    'airDate': airDate,
    'overview': overview,
    'hasFile': hasFile,
    'monitored': monitored,
    'runtime': runtime,
    'finaleType': finaleType,
    'episodeFile': file?.toJson(),
    'series': series?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SonarrEpisode &&
      other.id == id &&
      other.monitored == monitored &&
      other.hasFile == hasFile &&
      other.title == title &&
      other.airDateUtc == airDateUtc;

  @override
  int get hashCode => Object.hash(id, monitored, hasFile, title, airDateUtc);

  @override
  String toString() => 'SonarrEpisode($id)';
}
