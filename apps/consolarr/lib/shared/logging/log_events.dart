// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:observability/observability.dart';

/// App-level diagnostics lines. Each carries closed values only (a service
/// kind, an area name from a fixed set, an error category, a count): no host,
/// address, name, title or credential, so they stay safe by construction.
/// Messages are `snake_case_event key=value ...`.

/// The user made another server of [kind] the active one.
void logServerSwitch(AppLogger logger, ServiceKind kind) =>
    logger.info('server_switch kind=${kind.name}');

/// The active server of [kind] has no usable stored credentials.
void logNeedsCredentials(AppLogger logger, ServiceKind kind) =>
    logger.warning('needs_credentials kind=${kind.name}');

/// The features that can fall back to saved data. A closed set: the log line
/// can never carry a free-form string.
enum OfflineArea { sonarr, radarr, torrents }

/// A screen kept showing saved data because the live load failed with
/// [error].
void logOfflineFallback(AppLogger logger, OfflineArea area, AppError error) =>
    logger.info(
      'offline_fallback area=${area.name} category=${error.category.code}',
    );

/// Result of a connection test or health check of a [kind] server.
void logConnectionTest(AppLogger logger, ServiceKind kind, AppError? error) {
  final line =
      'connection_test kind=${kind.name} result=${error?.category.code ?? 'ok'}';
  if (error == null) {
    logger.info(line);
  } else {
    logger.warning(line);
  }
}
