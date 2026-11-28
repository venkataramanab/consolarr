// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/models.dart';
import 'package:arr_api/src/radarr/radarr_models.dart';
import 'package:arr_api/src/shared/arr_command.dart';
import 'package:arr_api/src/shared/arr_page.dart';
import 'package:arr_api/src/shared/arr_queue.dart';
import 'package:arr_api/src/shared/arr_release.dart';
import 'package:arr_api/src/sonarr/sonarr_episode.dart';
import 'package:arr_api/src/sonarr/sonarr_lookup.dart';
import 'package:arr_api/src/sonarr/sonarr_series_detail.dart';
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

  /// One series with every field (`GET api/v3/series/{id}`); `not_found`
  /// when it no longer exists.
  Future<Result<SonarrSeriesDetail>> seriesDetail(int id);

  /// Sends [payload] (see `SonarrSeriesDetail.editedPayload`) as the new
  /// series resource (`PUT api/v3/series/{id}`, never moving files).
  Future<Result<SonarrSeriesDetail>> updateSeries(
    int id,
    Map<String, Object?> payload,
  );

  /// Episodes of a series with their files (`GET api/v3/episode`).
  Future<Result<List<SonarrEpisode>>> episodes(int seriesId);

  /// Sets the monitored flag of episodes (`PUT api/v3/episode/monitor`, with
  /// a per-episode fallback on servers without that endpoint).
  Future<Result<void>> setEpisodesMonitored(
    List<int> episodeIds, {
    required bool monitored,
  });

  /// Episodes airing between [start] and [end] (`GET api/v3/calendar`), with
  /// their series.
  Future<Result<List<SonarrEpisode>>> calendar({
    required DateTime start,
    required DateTime end,
    bool includeUnmonitored = false,
  });

  /// The download queue (`GET api/v3/queue`, all pages up to a cap).
  Future<Result<List<ArrQueueItem>>> queue();

  /// Removes a queue item (`DELETE api/v3/queue/{id}`).
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  });

  /// Starts a command (`POST api/v3/command`).
  Future<Result<ArrCommand>> startCommand(ArrCommandRequest request);

  /// Reads a command (`GET api/v3/command/{id}`).
  Future<Result<ArrCommand>> command(int id);

  /// Releases found by an interactive search (`GET api/v3/release`): for an
  /// [episodeId], or a whole season ([seriesId] and [seasonNumber]).
  Future<Result<List<ArrRelease>>> releases({
    int? episodeId,
    int? seriesId,
    int? seasonNumber,
  });

  /// Grabs [release] (`POST api/v3/release`).
  Future<Result<void>> grabRelease(ArrRelease release);

  /// Wanted episodes (`GET api/v3/wanted/missing` or `wanted/cutoff`).
  Future<Result<ArrPage<SonarrEpisode>>> wanted(
    SonarrWantedKind kind, {
    int page = 1,
    int pageSize = 50,
  });

  /// Looks up series by title or `tvdb:123` / `imdb:tt123` style term.
  Future<Result<List<SonarrLookupResult>>> lookup(String term);

  /// Adds a looked-up series (`POST api/v3/series`).
  Future<Result<SonarrSeriesDetail>> addSeries(
    SonarrLookupResult lookup,
    SonarrAddOptions options,
  );

  /// Creates a tag (`POST api/v3/tag`).
  Future<Result<ArrTag>> createTag(String label);
}

/// Which wanted list to read.
enum SonarrWantedKind { missing, cutoffUnmet }

/// Answers every Sonarr-specific call with `not_found`. For test fakes:
/// mix it in and override only what the test needs, so fakes keep compiling
/// when [SonarrApi] grows.
mixin UnsupportedSonarrCalls implements SonarrApi {
  static const _none = AppError(ErrorCategory.notFound);

  @override
  Future<Result<SonarrSeriesDetail>> seriesDetail(int id) async =>
      const Result.err(_none);
  @override
  Future<Result<SonarrSeriesDetail>> updateSeries(
    int id,
    Map<String, Object?> payload,
  ) async => const Result.err(_none);
  @override
  Future<Result<List<SonarrEpisode>>> episodes(int seriesId) async =>
      const Result.err(_none);
  @override
  Future<Result<void>> setEpisodesMonitored(
    List<int> episodeIds, {
    required bool monitored,
  }) async => const Result.err(_none);
  @override
  Future<Result<List<SonarrEpisode>>> calendar({
    required DateTime start,
    required DateTime end,
    bool includeUnmonitored = false,
  }) async => const Result.err(_none);
  @override
  Future<Result<List<ArrQueueItem>>> queue() async => const Result.err(_none);
  @override
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  }) async => const Result.err(_none);
  @override
  Future<Result<ArrCommand>> startCommand(ArrCommandRequest request) async =>
      const Result.err(_none);
  @override
  Future<Result<ArrCommand>> command(int id) async => const Result.err(_none);
  @override
  Future<Result<List<ArrRelease>>> releases({
    int? episodeId,
    int? seriesId,
    int? seasonNumber,
  }) async => const Result.err(_none);
  @override
  Future<Result<void>> grabRelease(ArrRelease release) async =>
      const Result.err(_none);
  @override
  Future<Result<ArrPage<SonarrEpisode>>> wanted(
    SonarrWantedKind kind, {
    int page = 1,
    int pageSize = 50,
  }) async => const Result.err(_none);
  @override
  Future<Result<List<SonarrLookupResult>>> lookup(String term) async =>
      const Result.err(_none);
  @override
  Future<Result<SonarrSeriesDetail>> addSeries(
    SonarrLookupResult lookup,
    SonarrAddOptions options,
  ) async => const Result.err(_none);
  @override
  Future<Result<ArrTag>> createTag(String label) async =>
      const Result.err(_none);
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
  Future<Result<List<ArrQueueItem>>> queue();

  /// Removes a queue item (`DELETE api/v3/queue/{id}`).
  Future<Result<void>> removeQueueItem(
    int id, {
    required bool removeFromClient,
    required ArrBlocklistChoice blocklist,
  });

  /// Starts an automatic search for [movieIds] (`MoviesSearch`).
  Future<Result<ArrCommand>> searchMovies(List<int> movieIds);

  /// Starts a search for every missing movie (`MissingMoviesSearch`).
  Future<Result<ArrCommand>> searchAllMissing();

  /// A command's progress (`GET api/v3/command/{id}`).
  Future<Result<ArrCommand>> command(int id);

  /// Releases found by the indexers for [movieId] (`GET api/v3/release`).
  Future<Result<List<ArrRelease>>> releases(int movieId);

  /// Sends a release to the download client (`POST api/v3/release`).
  Future<Result<void>> grab(ArrRelease release);

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
