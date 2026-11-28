// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';

/// Small key/value preferences (view mode, saved sort/filter, default root
/// folder), keyed per server id by the callers.
abstract interface class RadarrPrefs {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// [RadarrPrefs] on the `AppStateRows` table.
class DriftRadarrPrefs implements RadarrPrefs {
  DriftRadarrPrefs(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.appStateRows,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String key, String value) => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(key: key, value: value),
      );
}

/// Key builders (`radarr.<thing>` and per server `radarr.<serverId>.<thing>`).
abstract final class RadarrPrefKeys {
  static const viewMode = 'radarr.view_mode';
  static String librarySort(String serverId) => 'radarr.$serverId.library.sort';
  static String libraryFilter(String serverId) =>
      'radarr.$serverId.library.filter';
  static String calendarTypes(String serverId) =>
      'radarr.$serverId.calendar.types';
  static String defaultRootFolder(String serverId) =>
      'radarr.$serverId.default_root_folder';
}
