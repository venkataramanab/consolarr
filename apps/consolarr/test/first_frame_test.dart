// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:security/security.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

void main() {
  testWidgets('no network or database access before the first frame', (
    tester,
  ) async {
    await expectNoIoBeforeFirstFrame(
      tester,
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.memory();
            ref.onDispose(db.close);
            return db;
          }),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        ],
        child: const ConsolarrApp(),
      ),
    );
    // And the first frame really was produced.
    expect(find.byType(ConsolarrApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
