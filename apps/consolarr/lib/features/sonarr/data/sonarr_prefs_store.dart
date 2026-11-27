// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';

/// Key/value preferences of the Sonarr area, one value per server and name
/// (`sonarr.<serverId>.<name>`), for saved sort/filter defaults and the
/// remembered root folder. Values are short strings (JSON by the caller);
/// they never hold secrets or server titles.
abstract interface class SonarrPrefsStore {
  Future<String?> read(String serverId, String name);
  Future<void> write(String serverId, String name, String value);
  Future<void> delete(String serverId, String name);
}

/// [SonarrPrefsStore] on the `AppStateRows` table.
class DriftSonarrPrefsStore implements SonarrPrefsStore {
  DriftSonarrPrefsStore(this._db);

  final AppDatabase _db;

  static String keyFor(String serverId, String name) =>
      'sonarr.$serverId.$name';

  @override
  Future<String?> read(String serverId, String name) async {
    final key = keyFor(serverId, name);
    final row = await (_db.select(
      _db.appStateRows,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String serverId, String name, String value) => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(key: keyFor(serverId, name), value: value),
      );

  @override
  Future<void> delete(String serverId, String name) => (_db.delete(
    _db.appStateRows,
  )..where((r) => r.key.equals(keyFor(serverId, name)))).go();
}

/// In-memory store for tests.
class MemorySonarrPrefsStore implements SonarrPrefsStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String serverId, String name) async =>
      values[DriftSonarrPrefsStore.keyFor(serverId, name)];

  @override
  Future<void> write(String serverId, String name, String value) async =>
      values[DriftSonarrPrefsStore.keyFor(serverId, name)] = value;

  @override
  Future<void> delete(String serverId, String name) async =>
      values.remove(DriftSonarrPrefsStore.keyFor(serverId, name));
}
