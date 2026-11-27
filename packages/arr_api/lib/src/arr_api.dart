// SPDX-License-Identifier: GPL-3.0-or-later

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
