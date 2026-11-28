// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/data/radarr_migration.dart';
import 'package:consolarr/features/settings/data/settings_migration.dart';
import 'package:consolarr/features/sonarr/data/sonarr_migration.dart';
import 'package:consolarr/features/torrents/data/torrents_migration.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/storage/pinned_marker_migration.dart';
import 'package:drift/drift.dart';

/// Upgrades one schema version.
typedef MigrationStep = Future<void> Function(Migrator m, AppDatabase db);

/// The schema version the skeleton shipped with (servers, payload cache, app
/// state).
const baseSchemaVersion = 1;

/// Every feature owns one schema version, allocated up front so parallel work
/// never collides on `schemaVersion`:
///
/// | version | owner    | tables                                       |
/// | ------- | -------- | -------------------------------------------- |
/// | 1       | skeleton | servers, cached payloads, app state          |
/// | 2       | sonarr   | `features/sonarr/data/sonarr_tables.drift`   |
/// | 3       | radarr   | `features/radarr/data/radarr_tables.drift`   |
/// | 4       | torrents | `features/torrents/data/torrents_tables.drift` |
/// | 5       | settings | `features/settings/data/settings_tables.drift` |
/// | 6       | storage  | `pinned_marker_rows` (pinned-without-pin guard) |
///
/// A feature creates its tables in its own step (`m.createTable(db.<table>)`)
/// and in nothing else. Versions are applied in order, so a database created
/// at version 1 reaches the current schema by running steps 2..5. New
/// installs run `createAll` and skip the steps. A change that needs a later
/// version is a new, appended slot (6, ...), never an edit of an existing one.
final Map<int, MigrationStep> migrationSteps = {
  2: sonarrMigration,
  3: radarrMigration,
  4: torrentsMigration,
  5: settingsMigration,
  6: pinnedMarkerMigration,
};

/// The version of the last slot.
int get currentSchemaVersion =>
    migrationSteps.keys.reduce((a, b) => a > b ? a : b);

/// Runs every step in `(from, to]` in order.
Future<void> runMigrations(
  Migrator m,
  AppDatabase db,
  int from,
  int to, {
  Map<int, MigrationStep>? steps,
}) async {
  final all = steps ?? migrationSteps;
  for (var version = from + 1; version <= to; version++) {
    final step = all[version];
    if (step == null) {
      throw StateError(
        'No migration step allocated for schema version $version',
      );
    }
    await step(m, db);
  }
}
