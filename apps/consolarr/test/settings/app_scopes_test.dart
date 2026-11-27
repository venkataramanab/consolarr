// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/src/providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/app_lock_gate.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:design_system/design_system.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

import 'support.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  SettingsHarness h, {
  List<Override> extra = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        ...extra,
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
  return ProviderScope.containerOf(tester.element(find.byType(ConsolarrApp)));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('settings that do not affect the themes do not rebuild '
      'MaterialApp, and the themes are built once per pair', (tester) async {
    final c = await _pump(tester, SettingsHarness());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final themes = c.read(appThemesProvider);
    final n = c.read(settingsProvider.notifier);

    await n.setLockDelay(LockDelay.fifteenMinutes);
    await n.setDiagnosticsLevel(LogLevel.debug);
    await n.setDiagnosticsEnabled(true);
    await n.setBlockScreenshots(true);
    await n.setMotion(MotionPreference.reduced);
    await n.setReduceTransparency(true);
    await tester.pumpAndSettle();
    expect(
      identical(tester.widget<MaterialApp>(find.byType(MaterialApp)), app),
      isTrue,
      reason: 'the root was not rebuilt',
    );
    expect(identical(c.read(appThemesProvider), themes), isTrue);

    // A theme input does rebuild it, with one new set of themes.
    await n.setHighContrast(true);
    await tester.pumpAndSettle();
    expect(identical(c.read(appThemesProvider), themes), isFalse);
    expect(
      identical(tester.widget<MaterialApp>(find.byType(MaterialApp)), app),
      isFalse,
    );
    await _unmount(tester);
  });

  testWidgets('in-app high contrast and reduce transparency make glass '
      'solid', (tester) async {
    final c = await _pump(tester, SettingsHarness());
    bool glass() =>
        ConsolarrEffects.of(tester.element(find.byType(AppLockGate))).useGlass;
    expect(glass(), isTrue);
    await c.read(settingsProvider.notifier).setHighContrast(true);
    await tester.pumpAndSettle();
    expect(glass(), isFalse);
    await c.read(settingsProvider.notifier).setHighContrast(false);
    await tester.pumpAndSettle();
    expect(glass(), isTrue);
    await c.read(settingsProvider.notifier).setReduceTransparency(true);
    await tester.pumpAndSettle();
    expect(glass(), isFalse);
    await _unmount(tester);
  });

  testWidgets('stored consent is applied by startup alone', (tester) async {
    // The shell reads the server list (and through it the consent-gated
    // analytics seam) after the first frame. Hold that list in `loading`, so
    // nothing else creates the consent manager: only the trigger in the app
    // root can. Removing that trigger makes this test fail.
    final h = SettingsHarness(stored: {SettingsKeys.consentCrashReports: '1'});
    final c = await _pump(
      tester,
      h,
      extra: [uiServersProvider.overrideWithValue(const AsyncValue.loading())],
    );
    expect(h.crash.enabledCalls, contains(true));
    expect(c.exists(consentManagerProvider), isTrue);
    await _unmount(tester);
  });
}
