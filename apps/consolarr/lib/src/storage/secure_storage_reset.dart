// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/data/drift_server_repository.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/storage/pinned_markers.dart';
import 'package:security/security.dart';

/// The user-confirmed recovery from an unreadable secret store: deletes every
/// stored secret (API keys, passwords, header values, certificate pins) and
/// the pinned markers. Servers then read "credentials needed"; a pinned
/// certificate has to be trusted again by hand.
///
/// Call it only after an explicit, destructive confirmation. Nothing in this
/// class runs on its own. A failed clear throws [SecretStoreUnavailable] and
/// leaves the markers in place (so a pin that may still exist is not
/// downgraded to first use).
class SecureStorageReset {
  SecureStorageReset({
    required SecretStore secrets,
    required PinnedMarkers markers,
    required AppDatabase db,
  }) : _secrets = secrets,
       _markers = markers,
       _db = db;

  final SecretStore _secrets;
  final PinnedMarkers _markers;
  final AppDatabase _db;

  Future<void> reset() async {
    await _secrets.deleteAll();
    await _markers.clear();
    // Live connections hold the old credentials; a new revision rebuilds them
    // and refreshes the list's "credentials needed" state.
    final rows = await _db.select(_db.serverRows).get();
    for (final id in [for (final r in rows) r.id]) {
      final key = DriftServerRepository.revisionKey(id);
      final row = await (_db.select(
        _db.appStateRows,
      )..where((r) => r.key.equals(key))).getSingleOrNull();
      final next = (int.tryParse(row?.value ?? '') ?? 0) + 1;
      await _db
          .into(_db.appStateRows)
          .insertOnConflictUpdate(
            AppStateRowsCompanion.insert(key: key, value: '$next'),
          );
    }
    await _db.customUpdate(
      'UPDATE server_rows SET sort_order = sort_order',
      updates: {_db.serverRows},
    );
  }
}
