// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';

/// Server profiles (drift) and their secrets (`SecretStore`).
///
/// Contract:
///  * `save` validates through `ServerProfile.parse` (credentials or query
///    strings in the address are rejected with `parse_error`), writes the row
///    and then the secrets (`<id>/api_key`, `<id>/username`, `<id>/password`,
///    `<id>/header/<name>`); secrets of an auth mode no longer used are
///    deleted.
///  * `delete` removes the row, its secrets, its pins and its cached payloads.
///  * A missing secret never throws: the entry reports `needsCredentials`.
abstract interface class ServerRepository {
  Stream<List<ServerEntry>> watchAll();

  Future<ServerEntry?> find(String id);

  Future<Result<ServerEntry>> save(ServerDraft draft);

  Future<void> delete(String id);

  /// Persists the given order (ids not listed keep their relative order after).
  Future<void> reorder(List<String> idsInOrder);

  /// `null` clears the startup server.
  Future<void> setStartup(String? id);

  /// The server used by default for [kind] (SRV-01 "set active").
  Future<void> setActive(ServiceKind kind, String id);

  /// The active server id for [kind]; falls back to the first server of that
  /// kind, or `null` when none exists.
  Future<String?> activeId(ServiceKind kind);

  /// Stored secrets for [profile]; missing values are `null`/absent.
  Future<ServerCredentials> loadCredentials(ServerProfile profile);
}

/// Runs the lightweight status/version query for a draft or stored server
/// (SRV-05, SRV-10). Never throws: failures are [ConnectionTestFailure].
abstract interface class ConnectionTester {
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials credentials,
  );
}
