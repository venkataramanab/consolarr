// SPDX-License-Identifier: GPL-3.0-or-later

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
/// prompt.
///
/// Implemented by the servers feature (`servers_providers.dart` overrides this
/// default); feature tests override it with a fake connection.
final activeConnectionProvider =
    FutureProvider.family<ServerConnection?, ServiceKind>(
      (ref, kind) => throw UnimplementedError(
        'activeConnectionProvider is wired by the servers feature',
      ),
    );
