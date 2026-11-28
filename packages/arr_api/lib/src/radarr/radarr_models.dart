// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/json_read.dart';
import 'package:core/core.dart';

/// Release status as reported by Radarr (`status`).
enum MovieStatus { tba, announced, inCinemas, released, deleted, unknown }

/// When a movie counts as available (`minimumAvailability`).
enum MinimumAvailability { tba, announced, inCinemas, released, unknown }

MovieStatus _status(String? v) => MovieStatus.values.firstWhere(
  (e) => e.name == v,
  orElse: () => MovieStatus.unknown,
);

MinimumAvailability _availability(String? v) => MinimumAvailability.values
    .firstWhere((e) => e.name == v, orElse: () => MinimumAvailability.unknown);

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The imported file of a movie (`movieFile`).
class MovieFile {
  const MovieFile({
    required this.id,
    this.size = 0,
    this.qualityName,
    this.resolution,
    this.videoCodec,
    this.audioCodec,
    this.dateAdded,
    this.relativePath,
  });

  factory MovieFile.fromJson(Map<String, Object?> json) {
    final quality = JsonRead.map(JsonRead.map(json['quality'])?['quality']);
    final media = JsonRead.map(json['mediaInfo']);
    return MovieFile(
      id: JsonRead.requiredInt(json, 'id'),
      size: JsonRead.integer(json, 'size'),
      qualityName: quality == null ? null : JsonRead.string(quality, 'name'),
      resolution: quality == null
          ? null
          : JsonRead.intOrNull(quality, 'resolution'),
      videoCodec: media == null ? null : JsonRead.string(media, 'videoCodec'),
      audioCodec: media == null ? null : JsonRead.string(media, 'audioCodec'),
      dateAdded: JsonRead.date(json, 'dateAdded'),
      relativePath: JsonRead.string(json, 'relativePath'),
    );
  }

  final int id;

  /// Bytes.
  final int size;
  final String? qualityName;
  final int? resolution;
  final String? videoCodec;
  final String? audioCodec;
  final DateTime? dateAdded;

  /// Server-side path (plain text, never logged).
  final String? relativePath;

  Map<String, Object?> toJson() => {
    'id': id,
    'size': size,
    'quality': {
      'quality': {'name': qualityName, 'resolution': resolution},
    },
    'mediaInfo': {'videoCodec': videoCodec, 'audioCodec': audioCodec},
    'dateAdded': _iso(dateAdded),
    'relativePath': relativePath,
  };

  @override
  bool operator ==(Object other) =>
      other is MovieFile &&
      other.id == id &&
      other.size == size &&
      other.qualityName == qualityName &&
      other.resolution == resolution &&
      other.videoCodec == videoCodec &&
      other.audioCodec == audioCodec &&
      other.dateAdded == dateAdded &&
      other.relativePath == relativePath;

  @override
  int get hashCode => Object.hash(
    id,
    size,
    qualityName,
    resolution,
    videoCodec,
    audioCodec,
    dateAdded,
    relativePath,
  );
}

/// A Radarr movie (v3 API). Server strings are plain text.
class RadarrMovie {
  const RadarrMovie({
    required this.id,
    required this.title,
    required this.sortTitle,
    this.year,
    this.status = MovieStatus.unknown,
    this.overview,
    this.monitored = false,
    this.minimumAvailability = MinimumAvailability.unknown,
    this.inCinemas,
    this.digitalRelease,
    this.physicalRelease,
    this.added,
    this.qualityProfileId,
    this.tags = const [],
    this.images = const [],
    this.hasFile = false,
    this.sizeOnDisk = 0,
    this.movieFile,
    this.runtime,
    this.studio,
    this.genres = const [],
    this.rating,
    this.popularity,
    this.collectionTitle,
    this.tmdbId,
    this.imdbId,
    this.youTubeTrailerId,
    this.certification,
  });

  /// Throws [FormatException] when `id` or `title` is missing or mistyped.
  factory RadarrMovie.fromJson(Map<String, Object?> json) {
    final title = JsonRead.requiredString(json, 'title');
    final year = JsonRead.intOrNull(json, 'year');
    final file = JsonRead.map(json['movieFile']);
    MovieFile? parsedFile;
    if (file != null) {
      try {
        parsedFile = MovieFile.fromJson(file);
      } on FormatException {
        parsedFile = null;
      }
    }
    final ratings = JsonRead.map(json['ratings']);
    double? rating;
    if (ratings != null) {
      for (final source in const ['tmdb', 'imdb']) {
        final value = JsonRead.map(ratings[source]);
        final v = value == null ? 0.0 : JsonRead.decimal(value, 'value');
        if (v > 0) {
          rating = v;
          break;
        }
      }
    }
    final collection = JsonRead.map(json['collection']);
    final popularity = JsonRead.decimal(json, 'popularity');
    final runtime = JsonRead.intOrNull(json, 'runtime');
    final trailer = JsonRead.string(json, 'youTubeTrailerId');
    return RadarrMovie(
      id: JsonRead.intOrNull(json, 'id') ?? 0,
      title: title,
      sortTitle: JsonRead.string(json, 'sortTitle') ?? title.toLowerCase(),
      year: year != null && year > 0 ? year : null,
      status: _status(JsonRead.string(json, 'status')),
      overview: JsonRead.string(json, 'overview'),
      monitored: JsonRead.boolean(json, 'monitored'),
      minimumAvailability: _availability(
        JsonRead.string(json, 'minimumAvailability'),
      ),
      inCinemas: JsonRead.date(json, 'inCinemas'),
      digitalRelease: JsonRead.date(json, 'digitalRelease'),
      physicalRelease: JsonRead.date(json, 'physicalRelease'),
      added: JsonRead.date(json, 'added'),
      qualityProfileId: JsonRead.intOrNull(json, 'qualityProfileId'),
      tags: [
        for (final t in JsonRead.list(json, 'tags'))
          if (t is int) t,
      ],
      images: [
        for (final i in JsonRead.list(json, 'images'))
          if (JsonRead.map(i) case final m?) ArrImage.fromJson(m),
      ],
      hasFile: JsonRead.boolean(json, 'hasFile') || parsedFile != null,
      sizeOnDisk: JsonRead.integer(json, 'sizeOnDisk') > 0
          ? JsonRead.integer(json, 'sizeOnDisk')
          : (parsedFile?.size ?? 0),
      movieFile: parsedFile,
      runtime: runtime != null && runtime > 0 ? runtime : null,
      studio: JsonRead.string(json, 'studio'),
      genres: [
        for (final g in JsonRead.list(json, 'genres'))
          if (g is String) g,
      ],
      rating: rating,
      popularity: popularity > 0 ? popularity : null,
      collectionTitle: collection == null
          ? null
          // v3 servers call it `name`.
          : JsonRead.string(collection, 'title') ??
                JsonRead.string(collection, 'name'),
      tmdbId: JsonRead.intOrNull(json, 'tmdbId'),
      imdbId: JsonRead.string(json, 'imdbId'),
      youTubeTrailerId: trailer == null || trailer.isEmpty ? null : trailer,
      certification: JsonRead.string(json, 'certification'),
    );
  }

  /// 0 for a lookup result that is not in the library.
  final int id;
  final String title;
  final String sortTitle;
  final int? year;
  final MovieStatus status;
  final String? overview;
  final bool monitored;
  final MinimumAvailability minimumAvailability;
  final DateTime? inCinemas;
  final DateTime? digitalRelease;
  final DateTime? physicalRelease;
  final DateTime? added;
  final int? qualityProfileId;
  final List<int> tags;
  final List<ArrImage> images;
  final bool hasFile;

  /// Bytes.
  final int sizeOnDisk;
  final MovieFile? movieFile;

  /// Minutes.
  final int? runtime;
  final String? studio;
  final List<String> genres;

  /// 0..10, TMDB first then IMDb.
  final double? rating;
  final double? popularity;

  /// Plain text only; the collection is never linked (no collection screen).
  final String? collectionTitle;
  final int? tmdbId;
  final String? imdbId;
  final String? youTubeTrailerId;
  final String? certification;

  /// Whether a lookup row is already part of the library.
  bool get inLibrary => id > 0;

  /// Cache format; parsed back by [RadarrMovie.fromJson].
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'sortTitle': sortTitle,
    'year': year,
    'status': status.name,
    'overview': overview,
    'monitored': monitored,
    'minimumAvailability': minimumAvailability.name,
    'inCinemas': _iso(inCinemas),
    'digitalRelease': _iso(digitalRelease),
    'physicalRelease': _iso(physicalRelease),
    'added': _iso(added),
    'qualityProfileId': qualityProfileId,
    'tags': tags,
    'images': [for (final i in images) i.toJson()],
    'hasFile': hasFile,
    'sizeOnDisk': sizeOnDisk,
    'movieFile': movieFile?.toJson(),
    'runtime': runtime,
    'studio': studio,
    'genres': genres,
    'ratings': {
      'tmdb': {'value': rating},
    },
    'popularity': popularity,
    'collection': collectionTitle == null ? null : {'title': collectionTitle},
    'tmdbId': tmdbId,
    'imdbId': imdbId,
    'youTubeTrailerId': youTubeTrailerId,
    'certification': certification,
  };

  @override
  bool operator ==(Object other) =>
      other is RadarrMovie &&
      other.id == id &&
      other.title == title &&
      other.sortTitle == sortTitle &&
      other.year == year &&
      other.status == status &&
      other.overview == overview &&
      other.monitored == monitored &&
      other.minimumAvailability == minimumAvailability &&
      other.inCinemas == inCinemas &&
      other.digitalRelease == digitalRelease &&
      other.physicalRelease == physicalRelease &&
      other.added == added &&
      other.qualityProfileId == qualityProfileId &&
      _listEq(other.tags, tags) &&
      _listEq(other.images, images) &&
      other.hasFile == hasFile &&
      other.sizeOnDisk == sizeOnDisk &&
      other.movieFile == movieFile &&
      other.runtime == runtime &&
      other.studio == studio &&
      _listEq(other.genres, genres) &&
      other.rating == rating &&
      other.popularity == popularity &&
      other.collectionTitle == collectionTitle &&
      other.tmdbId == tmdbId &&
      other.imdbId == imdbId &&
      other.youTubeTrailerId == youTubeTrailerId &&
      other.certification == certification;

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    sortTitle,
    year,
    status,
    overview,
    monitored,
    minimumAvailability,
    inCinemas,
    digitalRelease,
    physicalRelease,
    added,
    qualityProfileId,
    Object.hashAll(tags),
    Object.hashAll(images),
    hasFile,
    sizeOnDisk,
    movieFile,
    runtime,
    studio,
    Object.hashAll(genres),
    rating,
    popularity,
    collectionTitle,
    tmdbId,
    imdbId,
    youTubeTrailerId,
    certification,
  ]);

  /// Omits the title so logs never carry media titles.
  @override
  String toString() => 'RadarrMovie($id)';
}

/// Parses a movie array body. Malformed rows are skipped and counted; a body
/// where no row parses throws [FormatException]. Top level for isolates.
ParsedRows<RadarrMovie> parseMovieList(String body) =>
    parseArrList(jsonDecode(body), RadarrMovie.fromJson);

/// Parses one movie object body.
RadarrMovie parseMovie(String body) {
  final m = JsonRead.map(jsonDecode(body));
  if (m == null) throw const FormatException('expected an object');
  return RadarrMovie.fromJson(m);
}

/// What the add-movie request carries.
class AddMovieRequest {
  const AddMovieRequest({
    required this.lookup,
    required this.qualityProfileId,
    required this.rootFolderPath,
    required this.minimumAvailability,
    required this.monitored,
    this.tags = const [],
    this.searchForMovie = false,
    this.addCollection = false,
  });

  /// The lookup row being added.
  final RadarrMovie lookup;
  final int qualityProfileId;
  final String rootFolderPath;
  final MinimumAvailability minimumAvailability;
  final bool monitored;
  final List<int> tags;
  final bool searchForMovie;

  /// Adds the rest of the collection (monitored only). Only meaningful when
  /// the lookup carries a collection.
  final bool addCollection;
}

/// Wraps an [AppError] for validation problems found before any request.
AppError invalidRequest() =>
    const AppError(ErrorCategory.parseError, debugDetail: 'invalid_request');
