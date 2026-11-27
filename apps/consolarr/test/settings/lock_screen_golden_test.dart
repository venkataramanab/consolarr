// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:security/security.dart';

import 'support.dart';

Future<void> _golden(
  WidgetTester tester,
  String name, {
  required FakeDeviceAuthenticator auth,
  Size size = const Size(360, 800),
  double scale = 1,
  Locale? locale,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final h = SettingsHarness(
    stored: {
      ...lockOn(),
      if (locale != null) 'settings.locale': locale.languageCode,
    },
    auth: auth,
  );
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
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
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/lock_screen_$name.png'),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('golden: locked after a failed attempt', (tester) async {
    await _golden(
      tester,
      'failed_dark_en',
      auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
    );
  });

  testWidgets('golden: device lock removed, large text, small phone', (
    tester,
  ) async {
    await _golden(
      tester,
      'removed_en_320x568_x2',
      auth: FakeDeviceAuthenticator(
        supportResult: DeviceAuthSupport.noSecureLock,
      ),
      size: const Size(320, 568),
      scale: 2,
    );
  });
}
