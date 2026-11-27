// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/arr_common.dart';
import 'package:arr_api/src/models.dart';
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
abstract interface class RadarrApi implements ArrApi {}

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
