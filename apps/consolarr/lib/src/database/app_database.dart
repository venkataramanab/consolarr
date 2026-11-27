// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/src/database/migrations.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Server profiles (SRV-01..SRV-04). Holds NO secrets: API keys, passwords and
/// header values live in the `SecretStore`, referenced by [id].
class ServerRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `ServiceKind.name`.
  TextColumn get kind => text()();

  /// Origin (scheme, host, port); no credentials, no path.
  TextColumn get address => text()();

  /// Reserved second address (SRV-03); unused by the UI for now.
  TextColumn get alternateAddress => text().nullable()();
  TextColumn get pathPrefix => text().withDefault(const Constant(''))();

  /// `AuthMode.name`.
  TextColumn get authMode => text()();

  /// Custom header names, newline separated (values are secrets).
  TextColumn get headerNames => text().withDefault(const Constant(''))();
  BoolColumn get allowCleartext =>
      boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// The server opened on launch (at most one).
  BoolColumn get isStartup => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Last successful API payloads per server, for the offline view with an age
/// banner. Local cache only; excluded from backups with the rest of app data.
class CachedPayloadRows extends Table {
  TextColumn get serverId => text()();

  /// Feature-scoped key such as `sonarr.series`.
  TextColumn get key => text()();
  TextColumn get json => text()();
  IntColumn get fetchedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {serverId, key};
}

/// Key/value app state (active server per service kind, ...).
class AppStateRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [ServerRows, CachedPayloadRows, AppStateRows],
  // One SQL file per feature, so features add tables without touching this
  // file (see migrations.dart for the schema version each one owns).
  include: {
    '../../features/sonarr/data/sonarr_tables.drift',
    '../../features/radarr/data/radarr_tables.drift',
    '../../features/torrents/data/torrents_tables.drift',
    '../../features/settings/data/settings_tables.drift',
  },
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// The on-disk database. Nothing is opened until the first query, so
  /// constructing this before the first frame does no I/O.
  AppDatabase.onDisk()
    : super(
        LazyDatabase(() async {
          final dir = await getApplicationSupportDirectory();
          return NativeDatabase.createInBackground(
            File(p.join(dir.path, 'consolarr.sqlite')),
          );
        }),
      );

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) => runMigrations(m, this, from, to),
  );
}
