// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/auth_headers.dart';
import 'package:consolarr/features/servers/application/error_messages.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A ready-to-use connection to one configured server: the profile plus a Dio
/// from `SecureHttpClientFactory` that already carries the auth headers.
///
/// Service features (Sonarr, torrents) depend only on this type and
/// [activeConnectionProvider]; they never read secrets or build clients.
class ServerConnection {
  const ServerConnection({required this.profile, required this.dio});

  final ServerProfile profile;
  final Dio dio;
}

/// The connection for the active server of [ServiceKind], or `null` when no
/// server of that kind is configured. Fails with
/// `AppError(auth_failed, debugDetail: 'needs_credentials')` when the stored
/// secrets are missing (Keystore loss), so screens can show the re-entry
/// prompt. Rebuilds when the server list changes.
///
/// Feature tests override this with a fake connection.
/// Typed app errors (missing credentials, ...) are answers, not glitches:
/// never auto-retry them.
Duration? _noRetry(int retryCount, Object error) => null;

String _signature(List<ServerEntry> list) =>
    [for (final e in list) '${e.profile.hashCode}/${e.needsCredentials}']
        .join(',');

final activeConnectionProvider =
    FutureProvider.family<ServerConnection?, ServiceKind>(retry: _noRetry, (
      ref,
      kind,
    ) async {
      final repo = ref.watch(serverRepositoryProvider);
      // Rebuild when the server list really changes (not on first emission).
      final seen = _signature(await repo.watchAll().first);
      ref.listen(serversProvider, (_, next) {
        final list = next.value;
        if (list != null && _signature(list) != seen) ref.invalidateSelf();
      });
      final id = await repo.activeId(kind);
      if (id == null) return null;
      final entry = await repo.find(id);
      if (entry == null) return null;
      if (entry.needsCredentials) {
        throw const AppError(
          ErrorCategory.authFailed,
          debugDetail: needsCredentialsDetail,
        );
      }
      final credentials = await repo.loadCredentials(entry.profile);
      final dio = ref
          .watch(secureHttpClientFactoryProvider)
          .create(entry.profile);
      dio.options.headers.addAll(buildAuthHeaders(entry.profile, credentials));
      ref.onDispose(() => dio.close(force: true));
      return ServerConnection(profile: entry.profile, dio: dio);
    });
