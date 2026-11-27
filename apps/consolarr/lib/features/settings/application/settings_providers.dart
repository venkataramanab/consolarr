// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/data/external_actions.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// The key/value settings table. Lazy: the database opens on the first read,
/// which happens after the first frame.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => DriftSettingsStore(ref.watch(databaseProvider)),
);

/// The platform authenticator (device credential or biometric).
final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => PlatformDeviceAuthenticator(),
);

/// Browser, share sheet and platform facts.
final externalActionsProvider = Provider<ExternalActions>(
  (ref) => const PlatformExternalActions(),
);

/// User settings. Starts with defaults (dark theme, system language, lock
/// off) and applies the stored values after the first frame; nothing reads the
/// database before that.
class SettingsNotifier extends Notifier<AppSettings> {
  bool _loading = false;

  @override
  AppSettings build() {
    ref.listen<bool>(firstFrameDoneProvider, (_, done) {
      if (done) _load();
    });
    // Already past the first frame (a provider first read later): load right
    // after this build, not during it.
    if (ref.read(firstFrameDoneProvider)) Future.microtask(_load);
    return AppSettings.defaults;
  }

  Future<void> _load() async {
    if (_loading || state.loaded) return;
    _loading = true;
    try {
      final rows = await ref.read(settingsStoreProvider).readAll();
      if (!ref.mounted) return;
      state = AppSettings.fromRows(rows);
    } on Object {
      // Unreadable settings: keep the defaults, but do resolve the app (the
      // lock gate waits for this).
      if (ref.mounted) state = AppSettings.defaults.copyWith(loaded: true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _write(String key, String value) =>
      ref.read(settingsStoreProvider).write(key, value);

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _write(SettingsKeys.theme, mode.name);
  }

  /// `null` follows the system language.
  Future<void> setLocaleTag(String? tag) async {
    state = state.copyWith(localeTag: tag);
    await _write(SettingsKeys.locale, tag ?? '');
  }

  Future<void> setMotion(MotionPreference motion) async {
    state = state.copyWith(motion: motion);
    await _write(SettingsKeys.motion, motion.name);
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    await _write(SettingsKeys.highContrast, value ? '1' : '0');
  }

  Future<void> setLargerTargets(bool value) async {
    state = state.copyWith(largerTargets: value);
    await _write(SettingsKeys.largerTargets, value ? '1' : '0');
  }

  Future<void> setLockEnabled(bool value) async {
    state = state.copyWith(lockEnabled: value);
    await _write(SettingsKeys.lockEnabled, value ? '1' : '0');
  }

  Future<void> setLockDelay(LockDelay delay) async {
    state = state.copyWith(lockDelay: delay);
    await _write(SettingsKeys.lockDelay, delay.name);
  }

  Future<void> setBlockScreenshots(bool value) async {
    state = state.copyWith(blockScreenshots: value);
    await _write(SettingsKeys.blockScreenshots, value ? '1' : '0');
  }

  Future<void> setDiagnosticsEnabled(bool value) async {
    state = state.copyWith(diagnosticsEnabled: value);
    await _write(SettingsKeys.diagnosticsEnabled, value ? '1' : '0');
  }

  Future<void> setDiagnosticsLevel(LogLevel level) async {
    state = state.copyWith(diagnosticsLevel: level);
    await _write(SettingsKeys.diagnosticsLevel, level.name);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// The language the user picked, or `null` to follow the system.
final localeProvider = Provider<Locale?>(
  (ref) => ref.watch(settingsProvider.select((s) => s.locale)),
);

/// The in-app motion preference (SET-12).
final motionPreferenceProvider = Provider<MotionPreference>(
  (ref) => ref.watch(settingsProvider.select((s) => s.motion)),
);

/// The telemetry consent, off until the user switches it on (SET-03).
class ConsentNotifier extends Notifier<ConsentState> {
  @override
  ConsentState build() {
    final manager = ref.watch(consentManagerProvider);
    ref.listen<bool>(firstFrameDoneProvider, (_, done) async {
      if (!done) return;
      await manager.load();
      if (ref.mounted) state = manager.state;
    }, fireImmediately: true);
    return manager.state;
  }

  Future<void> set(ConsentPurpose purpose, {required bool enabled}) async {
    final manager = ref.read(consentManagerProvider);
    final before = manager.state;
    await manager.set(purpose, enabled: enabled);
    state = manager.state;
    if (before != manager.state) {
      // Gated: reaches analytics only when analytics consent is on.
      await ref
          .read(eventTrackerProvider)
          .track(ConsentChangedEvent(purpose: purpose.param, enabled: enabled));
    }
  }
}

final consentProvider = NotifierProvider<ConsentNotifier, ConsentState>(
  ConsentNotifier.new,
);

/// The opt-in in-app log (SET-04), fed by the redacting logger.
final diagnosticsLogProvider = Provider<DiagnosticsLog>((ref) {
  final log = DiagnosticsLog();
  ref.listen<AppSettings>(settingsProvider, (_, s) {
    log
      ..level = s.diagnosticsLevel
      ..enabled = s.diagnosticsEnabled;
  }, fireImmediately: true);
  return log;
});

/// Whether the device has a secure lock method app lock can use. Read when
/// the lock screen is opened, not before.
final deviceAuthSupportProvider = FutureProvider.autoDispose<DeviceAuthSupport>(
  (ref) => ref.watch(deviceAuthenticatorProvider).support(),
);

/// Whether this build can send telemetry at all (a reporting service has been
/// plugged in). The foss app cannot, and the privacy screen says so.
final telemetryAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(rawAnalyticsProvider) is! NoopAnalytics ||
      ref.watch(rawCrashReporterProvider) is! NoopCrashReporter,
);
