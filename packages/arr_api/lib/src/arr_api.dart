// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/models.dart';
import 'package:arr_api/src/radarr/radarr_models.dart';
import 'package:core/core.dart';

/// Shared surface of the *arr services.
abstract interface class ArrApi {
  ServiceKind get kind;

  /// Reads system status; doubles as a connection and version check.
  ///
  /// Fails with `unsupported_version` for major versions below the supported
  /// floor (SON-28).
  Future<Result<ArrSystemStatus>> systemStatus();

  /// Quality profiles (`api/v3/qualityprofile`). Malformed rows are skipped.
  Future<Result<List<ArrQualityProfile>>> qualityProfiles();

  /// Root folders (`api/v3/rootfolder`).
  Future<Result<List<ArrRootFolder>>> rootFolders();

  /// Tags (`api/v3/tag`).
  Future<Result<List<ArrTag>>> tags();
}

/// Sonarr (TV) API.
abstract interface class SonarrApi implements ArrApi {
  /// All series with statistics (`GET api/v3/series`).
  Future<Result<List<SonarrSeries>>> series();

  /// The authenticated-by-header artwork URL of [series], or null when the
  /// series has no such image. Never contains credentials.
  Uri? artworkUri(SonarrSeries series, SonarrImageType type);
}

/// Radarr (movies) API.
abstract interface class RadarrApi implements ArrApi {
  /// All movies (`GET api/v3/movie`).
  Future<Result<List<RadarrMovie>>> movies();

  /// One movie (`GET api/v3/movie/{id}`).
  Future<Result<RadarrMovie>> movie(int id);

  /// Movies with a release date in [start]..[end] (`GET api/v3/calendar`).
  Future<Result<List<RadarrMovie>>> calendar(DateTime start, DateTime end);

  /// Changes monitored, quality profile, minimum availability and tags of a
  /// movie. Reads the full object first and writes it back, so fields this
  /// app does not know survive. Never moves the movie.
  Future<Result<RadarrMovie>> updateMovie(
    int id, {
    bool? monitored,
    int? qualityProfileId,
    MinimumAvailability? minimumAvailability,
    List<int>? tags,
  });

  /// Title or external id lookup (`tmdb:123`, `imdb:tt123`, or free text).
  Future<Result<List<RadarrMovie>>> lookup(String term);

  /// Adds a movie (`POST api/v3/movie`).
  Future<Result<RadarrMovie>> addMovie(AddMovieRequest request);

  /// The download queue (`GET api/v3/queue`).
  Future<Result<List<RadarrQueueItem>>> queue();

  /// Removes a queue item (`DELETE api/v3/queue/{id}`).
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required QueueBlocklist blocklist,
  });

  /// Starts an automatic search for [movieIds] (`MoviesSearch`).
  Future<Result<RadarrCommand>> searchMovies(List<int> movieIds);

  /// Starts a search for every missing movie (`MissingMoviesSearch`).
  Future<Result<RadarrCommand>> searchAllMissing();

  /// A command's progress (`GET api/v3/command/{id}`).
  Future<Result<RadarrCommand>> command(int id);

  /// Releases found by the indexers for [movieId] (`GET api/v3/release`).
  Future<Result<List<RadarrRelease>>> releases(int movieId);

  /// Sends a release to the download client (`POST api/v3/release`).
  Future<Result<void>> grab(RadarrRelease release);

  /// The artwork URL of [movie], or null. Never contains credentials.
  Uri? artworkUri(RadarrMovie movie, ArrImageType type);
}

/// Answers the shared lists with empty successes. For test fakes (and stubs):
/// mix it in and override only what the test needs, so fakes keep compiling
/// when a shared method is added to [ArrApi].
mixin EmptyArrLists implements ArrApi {
  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() async =>
      const Result.ok([]);

  @override
  Future<Result<List<ArrRootFolder>>> rootFolders() async =>
      const Result.ok([]);

  @override
  Future<Result<List<ArrTag>>> tags() async => const Result.ok([]);
}
