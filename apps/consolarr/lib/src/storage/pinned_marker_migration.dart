// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:drift/drift.dart';

/// Schema version 6: the non-secret "this key was pinned" markers.
Future<void> pinnedMarkerMigration(Migrator m, AppDatabase db) =>
    m.createTable(db.pinnedMarkerRows);
