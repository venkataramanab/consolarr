// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';

/// The subset of `/system/status` the app needs first.
class ArrSystemStatus {
  const ArrSystemStatus({required this.version});

  /// Server version, e.g. `4.0.9.2244`. Drives version-gated behaviour.
  final String version;
}

/// Shared surface of the *arr services.
abstract interface class ArrApi {
  ServiceKind get kind;

  /// Reads system status; doubles as a connection and version check.
  Future<Result<ArrSystemStatus>> systemStatus();
}

/// Sonarr (TV) API.
abstract interface class SonarrApi implements ArrApi {}

/// Radarr (movies) API.
abstract interface class RadarrApi implements ArrApi {}
