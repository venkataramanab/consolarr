// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

import 'support.dart';

void main() {
  test('defaults: dark theme, system language, motion system, lock off', () {
    const s = AppSettings.defaults;
    expect(s.themeMode, ThemeMode.dark);
    expect(s.localeTag, isNull);
    expect(s.motion, MotionPreference.system);
    expect(s.highContrast, isFalse);
    expect(s.largerTargets, isFalse);
    expect(s.lockEnabled, isFalse);
    expect(s.lockDelay, LockDelay.immediately);
    expect(s.blockScreenshots, isFalse);
    expect(s.diagnosticsEnabled, isFalse);
    expect(s.touchTargets, TouchTargets.standard);
  });

  test('stored rows are parsed tolerantly', () {
    final s = AppSettings.fromRows({
      SettingsKeys.theme: 'nonsense',
      SettingsKeys.lockDelay: 'fiveMinutes',
      SettingsKeys.locale: 'ar',
      SettingsKeys.highContrast: '1',
      SettingsKeys.diagnosticsLevel: 'bogus',
    });
    expect(s.themeMode, ThemeMode.dark);
    expect(s.lockDelay, LockDelay.fiveMinutes);
    expect(s.locale, const Locale('ar'));
    expect(s.highContrast, isTrue);
    expect(s.diagnosticsLevel, LogLevel.info);
    expect(s.loaded, isTrue);
  });

  test('nothing is read before the first frame', () async {
    final h = SettingsHarness(stored: {SettingsKeys.theme: 'light'});
    final c = ProviderContainer(overrides: h.overrides);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    await h.settle(c);
    expect(c.read(settingsProvider).loaded, isFalse);
    c.read(firstFrameDoneProvider.notifier).markDone();
    await h.settle(c);
    expect(c.read(settingsProvider).loaded, isTrue);
    expect(c.read(themeModeProvider), ThemeMode.light);
  });

  test('changes apply at once and persist', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    final n = c.read(settingsProvider.notifier);
    await n.setThemeMode(ThemeMode.system);
    await n.setLocaleTag('ar');
    await n.setMotion(MotionPreference.reduced);
    await n.setHighContrast(true);
    await n.setLargerTargets(true);
    await n.setLockDelay(LockDelay.fifteenMinutes);
    await n.setBlockScreenshots(true);
    await n.setDiagnosticsEnabled(true);
    await n.setDiagnosticsLevel(LogLevel.debug);
    expect(c.read(themeModeProvider), ThemeMode.system);
    expect(c.read(localeProvider), const Locale('ar'));
    expect(c.read(motionPreferenceProvider), MotionPreference.reduced);

    // A new process with the same store sees the same values.
    final c2 = await h.startedContainer();
    final s = c2.read(settingsProvider);
    expect(s.themeMode, ThemeMode.system);
    expect(s.localeTag, 'ar');
    expect(s.motion, MotionPreference.reduced);
    expect(s.highContrast, isTrue);
    expect(s.largerTargets, isTrue);
    expect(s.lockDelay, LockDelay.fifteenMinutes);
    expect(s.blockScreenshots, isTrue);
    expect(s.diagnosticsEnabled, isTrue);
    expect(s.diagnosticsLevel, LogLevel.debug);
    c.dispose();
  });

  test('following the system language clears the stored tag', () async {
    final h = SettingsHarness(stored: {SettingsKeys.locale: 'ar'});
    final c = await h.startedContainer();
    expect(c.read(localeProvider), const Locale('ar'));
    await c.read(settingsProvider.notifier).setLocaleTag(null);
    expect(c.read(localeProvider), isNull);
    final c2 = await h.startedContainer();
    expect(c2.read(localeProvider), isNull);
  });

  test('no setting contains a secret-looking value', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    final n = c.read(settingsProvider.notifier);
    await n.setLockDelay(LockDelay.oneMinute);
    await n.setLockEnabled(true);
    for (final v in h.store.values.values) {
      expect(v.length, lessThan(24));
    }
    expect(
      h.store.values.keys.where(
        (k) => k.contains('pin') || k.contains('secret') || k.contains('key'),
      ),
      isEmpty,
    );
  });

  test('the diagnostics log follows the settings', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    final log = c.read(diagnosticsLogProvider);
    expect(log.enabled, isFalse);
    await c.read(settingsProvider.notifier).setDiagnosticsEnabled(true);
    await c.read(settingsProvider.notifier).setDiagnosticsLevel(LogLevel.error);
    expect(log.enabled, isTrue);
    expect(log.level, LogLevel.error);
    c.read(loggerProvider).error('boom');
    expect(log.entries.single.message, 'boom');
    await c.read(settingsProvider.notifier).setDiagnosticsEnabled(false);
    expect(log.entries, isEmpty);
  });

  test(
    'a failed write reverts the setting and logs only the error type',
    () async {
      final store = FailingWriteSettingsStore();
      final lines = <String>[];
      final h = SettingsHarness(store: store);
      final c = ProviderContainer(
        overrides: [
          ...h.overrides,
          settingsLoggerProvider.overrideWithValue(
            AppLogger(sink: (_, m) => lines.add(m)),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(firstFrameDoneProvider.notifier).markDone();
      c.read(settingsProvider);
      await h.settle(c);
      final n = c.read(settingsProvider.notifier);
      store.failWrites = true;
      expect(await n.setHighContrast(true), isFalse);
      expect(c.read(settingsProvider).highContrast, isFalse);
      expect(store.values.containsKey(SettingsKeys.highContrast), isFalse);
      expect(lines.single, contains('settings_write_failed'));
      expect(lines.single, isNot(contains('write failed')));
      store.failWrites = false;
      expect(await n.setHighContrast(true), isTrue);
      expect(c.read(settingsProvider).highContrast, isTrue);
    },
  );

  test('a failed write only reverts its own field', () async {
    final store = FailingWriteSettingsStore();
    final c = await SettingsHarness(store: store).startedContainer();
    final n = c.read(settingsProvider.notifier);
    await n.setLargerTargets(true);
    store.failWrites = true;
    await n.setHighContrast(true);
    expect(c.read(settingsProvider).largerTargets, isTrue);
    expect(c.read(settingsProvider).highContrast, isFalse);
  });
}
