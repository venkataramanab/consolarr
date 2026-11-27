// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';

/// How the series library is laid out (SON-01).
enum LibraryViewMode { grid, list }

/// Persists the chosen [LibraryViewMode].
abstract interface class ViewModeStore {
  Future<LibraryViewMode?> read();
  Future<void> write(LibraryViewMode mode);
}

/// [ViewModeStore] on the `AppStateRows` table.
class DriftViewModeStore implements ViewModeStore {
  DriftViewModeStore(this._db);

  /// Key in `AppStateRows`.
  static const key = 'sonarr.view_mode';

  final AppDatabase _db;

  @override
  Future<LibraryViewMode?> read() async {
    final row = await (_db.select(
      _db.appStateRows,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    for (final mode in LibraryViewMode.values) {
      if (mode.name == row.value) return mode;
    }
    return null;
  }

  @override
  Future<void> write(LibraryViewMode mode) => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(key: key, value: mode.name),
      );
}
