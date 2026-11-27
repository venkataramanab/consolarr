// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/database/migrations.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The skeleton's schema (version 1), as an installed app would have it.
const _v1Schema = [
  '''CREATE TABLE server_rows (
    id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
    address TEXT NOT NULL, alternate_address TEXT NULL,
    path_prefix TEXT NOT NULL DEFAULT '', auth_mode TEXT NOT NULL,
    header_names TEXT NOT NULL DEFAULT '',
    allow_cleartext INTEGER NOT NULL DEFAULT 0 CHECK (allow_cleartext IN (0, 1)),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_startup INTEGER NOT NULL DEFAULT 0 CHECK (is_startup IN (0, 1)))''',
  '''CREATE TABLE cached_payload_rows (
    server_id TEXT NOT NULL, "key" TEXT NOT NULL, json TEXT NOT NULL,
    fetched_at_ms INTEGER NOT NULL, PRIMARY KEY (server_id, "key"))''',
  '''CREATE TABLE app_state_rows (
    "key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)''',
  '''INSERT INTO server_rows (id, name, kind, address, auth_mode)
    VALUES ('s1', 'Example', 'sonarr', 'https://sonarr.example', 'apiKey')''',
];

void main() {
  test('every schema version from 2 to the current one has an owner', () {
    expect(baseSchemaVersion, 1);
    for (var v = baseSchemaVersion + 1; v <= currentSchemaVersion; v++) {
      expect(migrationSteps, contains(v), reason: 'version $v has no step');
    }
    expect(AppDatabase.memory().schemaVersion, currentSchemaVersion);
    expect(currentSchemaVersion, greaterThanOrEqualTo(5));
  });

  test(
    'a version 1 database upgrades through every slot and keeps its data',
    () async {
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            for (final sql in _v1Schema) {
              raw.execute(sql);
            }
            raw.execute('PRAGMA user_version = $baseSchemaVersion');
          },
        ),
      );
      addTearDown(db.close);
      final rows = await db.select(db.serverRows).get();
      expect(rows.single.id, 's1');
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], currentSchemaVersion);
    },
  );

  test('a missing slot fails loudly instead of skipping a version', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await expectLater(
      runMigrations(Migrator(db), db, 1, 3, steps: {2: (m, db) async {}}),
      throwsStateError,
    );
  });

  test('slots run in order', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final ran = <int>[];
    await runMigrations(
      Migrator(db),
      db,
      1,
      4,
      steps: {
        for (final v in [2, 3, 4]) v: (m, db) async => ran.add(v),
      },
    );
    expect(ran, [2, 3, 4]);
  });
}
