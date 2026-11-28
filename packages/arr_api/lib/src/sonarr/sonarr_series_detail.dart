// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/models.dart';
import 'package:core/core.dart';

/// A season of a series (`seasons[]`).
class SonarrSeason {
  const SonarrSeason({
    required this.number,
    this.monitored = false,
    this.statistics = const SeriesStatistics(),
  });

  factory SonarrSeason.fromJson(Map<String, Object?> json) {
    final stats = JsonRead.map(json['statistics']);
    return SonarrSeason(
      number: JsonRead.requiredInt(json, 'seasonNumber'),
      monitored: JsonRead.boolean(json, 'monitored'),
      statistics: stats == null
          ? const SeriesStatistics()
          : SeriesStatistics.fromJson(stats),
    );
  }

  final int number;
  final bool monitored;
  final SeriesStatistics statistics;
}

/// A rating (`ratings: {votes, value}`), value on a 0..10 scale.
class SonarrRating {
  const SonarrRating({required this.value, this.votes = 0});

  final double value;
  final int votes;
}

/// Identifier kinds the app can link out to.
enum SonarrExternalLinkKind { imdb, tvdb, tmdb, tvMaze }

/// An external information page built from a server-reported identifier.
///
/// Always an `https` URL on a fixed, known host: never a server-supplied
/// link. The identifier is validated per kind before the URL is built.
class SonarrExternalLink {
  const SonarrExternalLink(this.kind, this.uri);

  final SonarrExternalLinkKind kind;
  final Uri uri;
}

/// A full series resource (`GET /series/{id}`), tolerant of v3 and v4.
///
/// Keeps the raw payload so an edit can send back every field unchanged
/// (`PUT /series/{id}` replaces the whole resource) and only the edited ones
/// differ. Server text is plain text.
class SonarrSeriesDetail {
  const SonarrSeriesDetail({
    required this.summary,
    required this.raw,
    this.overview,
    this.path,
    this.rootFolderPath,
    this.genres = const [],
    this.seasons = const [],
    this.rating,
    this.certification,
    this.runtime,
    this.airTime,
    this.firstAired,
    this.previousAiring,
    this.seasonFolder = false,
    this.imdbId,
    this.tvdbId,
    this.tmdbId,
    this.tvMazeId,
    this.cast = const [],
  });

  factory SonarrSeriesDetail.fromJson(Map<String, Object?> json) {
    final summary = SonarrSeries.fromJson(json);
    final ratings = JsonRead.map(json['ratings']);
    final value = ratings == null ? 0.0 : JsonRead.decimal(ratings, 'value');
    final seasons = [
      for (final s in JsonRead.list(json, 'seasons'))
        if (JsonRead.map(s) case final m?)
          if (m['seasonNumber'] is int) SonarrSeason.fromJson(m),
    ]..sort((a, b) => b.number.compareTo(a.number));
    return SonarrSeriesDetail(
      summary: summary,
      raw: Map<String, Object?>.unmodifiable(json),
      overview: _nonEmpty(JsonRead.string(json, 'overview')),
      path: _nonEmpty(JsonRead.string(json, 'path')),
      rootFolderPath: _nonEmpty(JsonRead.string(json, 'rootFolderPath')),
      genres: [
        for (final g in JsonRead.list(json, 'genres'))
          if (g is String && g.isNotEmpty) g,
      ],
      seasons: seasons,
      rating: value > 0
          ? SonarrRating(
              value: value,
              votes: JsonRead.integer(ratings!, 'votes'),
            )
          : null,
      certification: _nonEmpty(JsonRead.string(json, 'certification')),
      runtime: _positive(JsonRead.intOrNull(json, 'runtime')),
      airTime: _nonEmpty(JsonRead.string(json, 'airTime')),
      firstAired: JsonRead.date(json, 'firstAired'),
      previousAiring: JsonRead.date(json, 'previousAiring'),
      seasonFolder: JsonRead.boolean(json, 'seasonFolder'),
      imdbId: _nonEmpty(JsonRead.string(json, 'imdbId')),
      tvdbId: _positive(JsonRead.intOrNull(json, 'tvdbId')),
      tmdbId: _positive(JsonRead.intOrNull(json, 'tmdbId')),
      tvMazeId: _positive(JsonRead.intOrNull(json, 'tvMazeId')),
      cast: [
        for (final c in JsonRead.list(json, 'cast'))
          if (JsonRead.map(c) case final m?)
            if (JsonRead.string(m, 'name') case final n? when n.isNotEmpty) n,
      ],
    );
  }

  /// The list-level fields (title, status, artwork, statistics, ...).
  final SonarrSeries summary;

  /// The payload as received, for a lossless update.
  final Map<String, Object?> raw;
  final String? overview;
  final String? path;
  final String? rootFolderPath;
  final List<String> genres;

  /// Newest season first.
  final List<SonarrSeason> seasons;
  final SonarrRating? rating;
  final String? certification;
  final int? runtime;
  final String? airTime;
  final DateTime? firstAired;
  final DateTime? previousAiring;
  final bool seasonFolder;
  final String? imdbId;
  final int? tvdbId;
  final int? tmdbId;
  final int? tvMazeId;

  /// Cast names; only present on servers that report them.
  final List<String> cast;

  int get id => summary.id;

  /// Links to information pages, built from validated identifiers only.
  List<SonarrExternalLink> get externalLinks => [
    if (imdbId != null && RegExp(r'^tt\d{1,12}$').hasMatch(imdbId!))
      SonarrExternalLink(
        SonarrExternalLinkKind.imdb,
        Uri.https(ExternalHosts.imdb, '/title/$imdbId/'),
      ),
    if (tvdbId != null)
      SonarrExternalLink(
        SonarrExternalLinkKind.tvdb,
        Uri.https(ExternalHosts.tvdb, '/', {'tab': 'series', 'id': '$tvdbId'}),
      ),
    if (tmdbId != null)
      SonarrExternalLink(
        SonarrExternalLinkKind.tmdb,
        Uri.https(ExternalHosts.tmdb, '/tv/$tmdbId'),
      ),
    if (tvMazeId != null)
      SonarrExternalLink(
        SonarrExternalLinkKind.tvMaze,
        Uri.https(ExternalHosts.tvMaze, '/shows/$tvMazeId'),
      ),
  ];

  /// A copy of the payload with the editable fields changed, ready for
  /// `PUT`. Season monitoring is changed through [seasonMonitored].
  Map<String, Object?> editedPayload({
    bool? monitored,
    int? qualityProfileId,
    List<int>? tags,
    Map<int, bool>? seasonMonitored,
  }) {
    final out = Map<String, Object?>.of(raw);
    if (monitored != null) out['monitored'] = monitored;
    if (qualityProfileId != null) out['qualityProfileId'] = qualityProfileId;
    if (tags != null) out['tags'] = tags;
    if (seasonMonitored != null && seasonMonitored.isNotEmpty) {
      out['seasons'] = [
        for (final s in JsonRead.list(raw, 'seasons'))
          if (JsonRead.map(s) case final m?)
            if (m['seasonNumber'] is int &&
                seasonMonitored.containsKey(m['seasonNumber']))
              {...m, 'monitored': seasonMonitored[m['seasonNumber']]}
            else
              m,
      ];
    }
    return out;
  }

  /// Cache format: the raw payload.
  Map<String, Object?> toJson() => raw;

  @override
  String toString() => 'SonarrSeriesDetail($id)';
}

String? _nonEmpty(String? v) => v == null || v.trim().isEmpty ? null : v;
int? _positive(int? v) => v != null && v > 0 ? v : null;

/// Series image helper re-exported for detail artwork (fanart backdrop).
List<ArrImage> imagesOf(SonarrSeriesDetail d) => d.summary.images;
