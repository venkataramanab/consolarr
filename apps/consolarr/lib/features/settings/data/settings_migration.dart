// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:drift/drift.dart';

/// The schema step this feature owns (see `lib/src/database/migrations.dart`
/// for the version table). Create the feature's tables here, for example
/// `await m.createTable(db.<table>);`. Empty until the feature has tables.
Future<void> settingsMigration(Migrator m, AppDatabase db) async {}
