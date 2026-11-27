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

/// The stored settings and consent rows, read **once** (after the first
/// frame) and shared by [SettingsNotifier] and the consent store. Invalidated
/// to read again after a failure.
final storedRowsProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.read(settingsStoreProvider).readAll(),
  retry: (_, _) => null,
);

/// The logger for settings write failures (error type only). A seam of its
/// own: the app logger depends on the settings, so the notifier cannot read
/// it without a cycle. Redacting, like every logger.
final settingsLoggerProvider = Provider<AppLogger>((ref) => AppLogger());

/// User settings. Starts with defaults (dark theme, system language, lock
/// off) and applies the stored values after the first frame; nothing reads the
/// database before that.
///
/// If the stored values cannot be read (after one retry) the state is
/// `loadFailed`: the app fails closed (see `AppLockController`) instead of
/// opening unlocked on defaults.
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
      // One retry, then fail closed.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final rows = await ref.read(storedRowsProvider.future);
          if (!ref.mounted) return;
          state = AppSettings.fromRows(rows);
          return;
        } on Object {
          if (!ref.mounted) return;
          ref.invalidate(storedRowsProvider);
        }
      }
      state = AppSettings.defaults.copyWith(loaded: true, loadFailed: true);
    } finally {
      _loading = false;
    }
  }

  /// Reads the stored values again (the "try again" of the fail-closed
  /// screen).
  Future<void> reload() async {
    if (_loading) return;
    ref.invalidate(storedRowsProvider);
    // Not the plain defaults: `loadFailed` stays set so the window stays
    // secure (and the content hidden) until the new read resolves.
    state = AppSettings.defaults.copyWith(loadFailed: true);
    await _load();
  }

  /// Applies [value] at once and persists it. If the write fails the field is
  /// reverted (only that field) so what is shown matches what is stored, and
  /// only the error type is logged. Returns whether the value was stored.
  Future<bool> _commit<T>(
    T value, {
    required T Function(AppSettings) read,
    required AppSettings Function(AppSettings, T) write,
    required String key,
    required String stored,
  }) async {
    final before = read(state);
    state = write(state, value);
    try {
      await ref.read(settingsStoreProvider).write(key, stored);
      return true;
    } on Object catch (e) {
      if (ref.mounted) {
        state = write(state, before);
        ref
            .read(settingsLoggerProvider)
            .warning('settings_write_failed ${e.runtimeType}');
      }
      return false;
    }
  }

  Future<bool> setThemeMode(ThemeMode mode) => _commit(
    mode,
    read: (s) => s.themeMode,
    write: (s, v) => s.copyWith(themeMode: v),
    key: SettingsKeys.theme,
    stored: mode.name,
  );

  /// `null` follows the system language.
  Future<bool> setLocaleTag(String? tag) => _commit(
    tag,
    read: (s) => s.localeTag,
    write: (s, v) => s.copyWith(localeTag: v),
    key: SettingsKeys.locale,
    stored: tag ?? '',
  );

  Future<bool> setMotion(MotionPreference motion) => _commit(
    motion,
    read: (s) => s.motion,
    write: (s, v) => s.copyWith(motion: v),
    key: SettingsKeys.motion,
    stored: motion.name,
  );

  Future<bool> setHighContrast(bool value) => _commit(
    value,
    read: (s) => s.highContrast,
    write: (s, v) => s.copyWith(highContrast: v),
    key: SettingsKeys.highContrast,
    stored: value ? '1' : '0',
  );

  Future<bool> setLargerTargets(bool value) => _commit(
    value,
    read: (s) => s.largerTargets,
    write: (s, v) => s.copyWith(largerTargets: v),
    key: SettingsKeys.largerTargets,
    stored: value ? '1' : '0',
  );

  Future<bool> setReduceTransparency(bool value) => _commit(
    value,
    read: (s) => s.reduceTransparency,
    write: (s, v) => s.copyWith(reduceTransparency: v),
    key: SettingsKeys.reduceTransparency,
    stored: value ? '1' : '0',
  );

  Future<bool> setLockEnabled(bool value) => _commit(
    value,
    read: (s) => s.lockEnabled,
    write: (s, v) => s.copyWith(lockEnabled: v),
    key: SettingsKeys.lockEnabled,
    stored: value ? '1' : '0',
  );

  Future<bool> setLockDelay(LockDelay delay) => _commit(
    delay,
    read: (s) => s.lockDelay,
    write: (s, v) => s.copyWith(lockDelay: v),
    key: SettingsKeys.lockDelay,
    stored: delay.name,
  );

  Future<bool> setBlockScreenshots(bool value) => _commit(
    value,
    read: (s) => s.blockScreenshots,
    write: (s, v) => s.copyWith(blockScreenshots: v),
    key: SettingsKeys.blockScreenshots,
    stored: value ? '1' : '0',
  );

  Future<bool> setDiagnosticsEnabled(bool value) => _commit(
    value,
    read: (s) => s.diagnosticsEnabled,
    write: (s, v) => s.copyWith(diagnosticsEnabled: v),
    key: SettingsKeys.diagnosticsEnabled,
    stored: value ? '1' : '0',
  );

  Future<bool> setDiagnosticsLevel(LogLevel level) => _commit(
    level,
    read: (s) => s.diagnosticsLevel,
    write: (s, v) => s.copyWith(diagnosticsLevel: v),
    key: SettingsKeys.diagnosticsLevel,
    stored: level.name,
  );
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

/// The telemetry consent, off until the user switches it on (SET-03). The
/// stored choice is loaded by `consentManagerProvider` right after the first
/// frame; this notifier only mirrors it for the UI.
class ConsentNotifier extends Notifier<ConsentState> {
  @override
  ConsentState build() {
    final manager = ref.watch(consentManagerProvider);
    void listener() {
      if (ref.mounted) state = manager.state;
    }

    manager.addListener(listener);
    ref.onDispose(() => manager.removeListener(listener));
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
  final log = DiagnosticsLog(clock: ref.read(clockProvider));
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
