// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:drift/drift.dart';

/// A cached API payload and when it was fetched.
class CachedPayload {
  const CachedPayload({required this.json, required this.fetchedAt});
  final String json;
  final DateTime fetchedAt;
}

/// Last good API payload per server and key, for the offline view that shows
/// cached data under an age banner. Keys are feature scoped
/// (`sonarr.series`). Payloads are server data (titles), so they are only ever
/// stored locally and never logged or reported.
abstract interface class PayloadCache {
  Future<CachedPayload?> read(String serverId, String key);
  Future<void> write(
    String serverId,
    String key,
    String json,
    DateTime fetchedAt,
  );
  Future<void> deleteForServer(String serverId);

  /// Removes one row.
  Future<void> delete(String serverId, String key);

  /// Removes every row whose key starts with [keyPrefix] (a plain prefix, no
  /// wildcards) and whose server is not in [keepServerIds] (rows left behind
  /// by a deleted server).
  Future<void> pruneKeys(String keyPrefix, Set<String> keepServerIds);
}

/// [PayloadCache] on the app drift database.
class DriftPayloadCache implements PayloadCache {
  DriftPayloadCache(this._db);

  final AppDatabase _db;

  @override
  Future<CachedPayload?> read(String serverId, String key) async {
    final row =
        await (_db.select(_db.cachedPayloadRows)
              ..where((r) => r.serverId.equals(serverId) & r.key.equals(key)))
            .getSingleOrNull();
    if (row == null) return null;
    return CachedPayload(
      json: row.json,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        row.fetchedAtMs,
        isUtc: true,
      ),
    );
  }

  @override
  Future<void> write(
    String serverId,
    String key,
    String json,
    DateTime fetchedAt,
  ) => _db
      .into(_db.cachedPayloadRows)
      .insertOnConflictUpdate(
        CachedPayloadRowsCompanion.insert(
          serverId: serverId,
          key: key,
          json: json,
          fetchedAtMs: fetchedAt.millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> deleteForServer(String serverId) => (_db.delete(
    _db.cachedPayloadRows,
  )..where((r) => r.serverId.equals(serverId))).go();

  @override
  Future<void> delete(String serverId, String key) =>
      (_db.delete(_db.cachedPayloadRows)
            ..where((r) => r.serverId.equals(serverId) & r.key.equals(key)))
          .go();

  @override
  Future<void> pruneKeys(String keyPrefix, Set<String> keepServerIds) =>
      (_db.delete(_db.cachedPayloadRows)..where(
            (r) =>
                r.key.like('$keyPrefix%') &
                r.serverId.isNotIn(keepServerIds),
          ))
          .go();
}
