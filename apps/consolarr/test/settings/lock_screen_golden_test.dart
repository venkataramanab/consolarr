// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
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
  int taps = 0,
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
  for (var i = 0; i < taps; i++) {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }
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

  testWidgets('golden: locked, prompt pending', (tester) async {
    final auth = FakeDeviceAuthenticator()
      ..hold = Completer<DeviceAuthResult>();
    await _golden(tester, 'locked_dark_en', auth: auth);
    await _golden(
      tester,
      'locked_ar_320x568_x2',
      auth: FakeDeviceAuthenticator()..hold = Completer<DeviceAuthResult>(),
      size: const Size(320, 568),
      scale: 2,
      locale: const Locale('ar'),
    );
  });

  testWidgets('golden: cool-down after three failures', (tester) async {
    for (final (name, size, scale, locale) in [
      ('cooldown_dark_en', const Size(360, 800), 1.0, null),
      ('cooldown_ar_320x568_x2', const Size(320, 568), 2.0, const Locale('ar')),
    ]) {
      await _golden(
        tester,
        name,
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
        size: size,
        scale: scale,
        locale: locale,
        taps: lockMaxAttempts - 1,
      );
    }
  });

  testWidgets('golden: biometrics unavailable', (tester) async {
    for (final (name, size, scale, locale) in [
      ('no_biometrics_dark_en', const Size(360, 800), 1.0, null),
      (
        'no_biometrics_ar_320x568_x2',
        const Size(320, 568),
        2.0,
        const Locale('ar'),
      ),
    ]) {
      await _golden(
        tester,
        name,
        auth: FakeDeviceAuthenticator(
          biometrics: false,
          results: [DeviceAuthResult.failed],
        ),
        size: size,
        scale: scale,
        locale: locale,
      );
    }
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
