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

/// The active server of [ServiceKind] plus the save revision (see
/// `ServerRepository.watchConnectionKey`). Everything that must follow the
/// active server or its credentials watches this provider; no screen needs to
/// invalidate anything by hand after `setActive` or `save`.
final activeConnectionKeyProvider =
    StreamProvider.family<ConnectionKey, ServiceKind>(
      (ref, kind) =>
          ref.watch(serverRepositoryProvider).watchConnectionKey(kind),
    );

/// Typed app errors (missing credentials, ...) are answers, not glitches:
/// never auto-retry them.
Duration? _noRetry(int retryCount, Object error) => null;

/// The connection for the active server of [ServiceKind], or `null` when no
/// server of that kind is configured. Fails with
/// `AppError(auth_failed, debugDetail: 'needs_credentials')` when the stored
/// secrets are missing (Keystore loss), so screens can show the re-entry
/// prompt. Rebuilds whenever the active server or any saved data changes
/// ([activeConnectionKeyProvider]); a rebuild creates a fresh Dio with the
/// new auth headers and closes the old one.
///
/// Feature tests override this with a fake connection.
final activeConnectionProvider =
    FutureProvider.family<ServerConnection?, ServiceKind>(retry: _noRetry, (
      ref,
      kind,
    ) async {
      final repo = ref.watch(serverRepositoryProvider);
      // A plain stream subscription, not `ref.watch(keyProvider.future)`:
      // Riverpod pauses the dependencies of a provider nobody listens to yet,
      // which would starve the first read of this provider.
      final key = await repo.watchConnectionKey(kind).first;
      // The new subscription replays the current value first, so a change
      // between the read above and this listen is still noticed.
      final sub = repo.watchConnectionKey(kind).listen((next) {
        if (next != key) ref.invalidateSelf();
      });
      ref.onDispose(sub.cancel);
      final id = key.serverId;
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
