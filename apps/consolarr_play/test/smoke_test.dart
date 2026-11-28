// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('play entry point renders the shared app', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The lock gate waits for the stored settings; keep them in memory.
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          // The dashboard (the home screen) shows skeletons until the server
          // list answers, so the database must answer: use an in-memory one.
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.memory();
            ref.onDispose(db.close);
            return db;
          }),
        ],
        child: const ConsolarrApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
    // Unmount so the database stream's cleanup timer fires before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
