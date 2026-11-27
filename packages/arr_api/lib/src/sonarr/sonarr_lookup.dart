// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/models.dart';

/// A result of `GET /series/lookup`.
///
/// Keeps the raw payload: adding a series sends the lookup resource back with
/// the user's options applied. A series already in the library has an `id`.
class SonarrLookupResult {
  const SonarrLookupResult({
    required this.series,
    required this.raw,
    this.tvdbId,
    this.overview,
  });

  factory SonarrLookupResult.fromJson(Map<String, Object?> json) {
    // Lookup resources have no id until added; give the summary a stable one.
    final series = SonarrSeries.fromJson({
      ...json,
      'id': JsonRead.intOrNull(json, 'id') ?? 0,
    });
    return SonarrLookupResult(
      series: series,
      raw: Map<String, Object?>.unmodifiable(json),
      tvdbId: JsonRead.intOrNull(json, 'tvdbId'),
      overview: JsonRead.string(json, 'overview'),
    );
  }

  final SonarrSeries series;
  final Map<String, Object?> raw;
  final int? tvdbId;
  final String? overview;

  /// Library id when the series already exists.
  int? get libraryId => series.id > 0 ? series.id : null;

  bool get inLibrary => series.id > 0;

  @override
  String toString() => 'SonarrLookupResult($tvdbId)';
}

/// Which episodes to monitor when adding (`addOptions.monitor`).
enum SonarrMonitorPreset {
  all,
  future,
  missing,
  existing,
  firstSeason,
  lastSeason,
  latestSeason,
  pilot,
  none,
}

/// Everything the user chooses when adding a series.
class SonarrAddOptions {
  const SonarrAddOptions({
    required this.qualityProfileId,
    required this.rootFolderPath,
    this.seriesType = SeriesType.standard,
    this.monitor = SonarrMonitorPreset.all,
    this.seasonFolder = true,
    this.monitored = true,
    this.tags = const [],
    this.searchForMissing = false,
  });

  final int qualityProfileId;
  final String rootFolderPath;
  final SeriesType seriesType;
  final SonarrMonitorPreset monitor;
  final bool seasonFolder;
  final bool monitored;
  final List<int> tags;

  /// "Add and search": search for missing episodes right after adding.
  final bool searchForMissing;
}
