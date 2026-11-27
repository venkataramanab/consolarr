// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything a Sonarr repository or controller needs for the *active*
/// server: the API, the server id (cache and preference keys), the payload
/// cache and the clock.
///
/// A new session is created whenever the active server or its credentials
/// change (it rebuilds from `activeConnectionProvider`), so anything watching
/// [sonarrSessionProvider] reloads on a server switch. Tests override this
/// provider with a session around a fake API.
class SonarrSession {
  const SonarrSession({
    required this.api,
    required this.serverId,
    required this.cache,
    required this.clock,
    this.dio,
  });

  final SonarrApi api;
  final String serverId;
  final PayloadCache cache;
  final DateTime Function() clock;

  /// The secure client (artwork). Null in tests that do not load images.
  final Dio? dio;
}

/// The session for the active Sonarr server, or `null` without one. Fails
/// with the connection's [AppError] (for example missing credentials).
final sonarrSessionProvider = FutureProvider<SonarrSession?>(
  retry: (_, _) => null,
  (ref) async {
    final connection = await ref.watch(
      activeConnectionProvider(ServiceKind.sonarr).future,
    );
    if (connection == null) return null;
    return SonarrSession(
      api: SonarrClient(
        dio: connection.dio,
        onRowsSkipped: (count) => ref
            .read(loggerProvider)
            .info('skipped $count malformed sonarr rows'),
      ),
      serverId: connection.profile.id,
      cache: ref.watch(payloadCacheProvider),
      clock: ref.watch(clockProvider),
      dio: connection.dio,
    );
  },
);

/// Small per-server preferences (saved sort/filter, default root folder).
final sonarrPrefsStoreProvider = Provider<SonarrPrefsStore>(
  (ref) => DriftSonarrPrefsStore(ref.watch(databaseProvider)),
);
