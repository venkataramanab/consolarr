// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// How long the app may be in the background before it locks again (SET-02).
enum LockDelay {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15));

  const LockDelay(this.duration);

  final Duration duration;
}

/// Non-secret app state kept in the key/value `AppStateRows` table. None of it
/// is a credential: the lock itself is the device authenticator.
@immutable
class AppSettings {
  const AppSettings({
    this.loaded = false,
    this.loadFailed = false,
    this.themeMode = ThemeMode.dark,
    this.localeTag,
    this.motion = MotionPreference.system,
    this.highContrast = false,
    this.largerTargets = false,
    this.lockEnabled = false,
    this.lockDelay = LockDelay.immediately,
    this.blockScreenshots = false,
    this.diagnosticsEnabled = false,
    this.diagnosticsLevel = LogLevel.info,
  });

  /// Defaults until the stored values have been read (after the first frame).
  static const defaults = AppSettings();

  /// Whether the stored values have been applied (or reading them failed).
  final bool loaded;

  /// The stored values could not be read (after one retry). The defaults are
  /// in effect, but the app must **fail closed**: no content, secure window.
  final bool loadFailed;

  /// Dark by default (the identity), light, or follow the system.
  final ThemeMode themeMode;

  /// `null` follows the system language; otherwise a language tag such as
  /// `ar` or `en`.
  final String? localeTag;
  final MotionPreference motion;
  final bool highContrast;
  final bool largerTargets;
  final bool lockEnabled;
  final LockDelay lockDelay;
  final bool blockScreenshots;
  final bool diagnosticsEnabled;
  final LogLevel diagnosticsLevel;

  /// The window must be marked secure (blank recents thumbnail, no
  /// screenshots): the lock needs it, and so does the explicit switch.
  bool get wantsSecureWindow => lockEnabled || blockScreenshots || loadFailed;

  Locale? get locale => localeTag == null ? null : Locale(localeTag!);

  TouchTargets get touchTargets =>
      largerTargets ? TouchTargets.large : TouchTargets.standard;

  AppSettings copyWith({
    bool? loaded,
    bool? loadFailed,
    ThemeMode? themeMode,
    Object? localeTag = _keep,
    MotionPreference? motion,
    bool? highContrast,
    bool? largerTargets,
    bool? lockEnabled,
    LockDelay? lockDelay,
    bool? blockScreenshots,
    bool? diagnosticsEnabled,
    LogLevel? diagnosticsLevel,
  }) => AppSettings(
    loaded: loaded ?? this.loaded,
    loadFailed: loadFailed ?? this.loadFailed,
    themeMode: themeMode ?? this.themeMode,
    localeTag: identical(localeTag, _keep)
        ? this.localeTag
        : localeTag as String?,
    motion: motion ?? this.motion,
    highContrast: highContrast ?? this.highContrast,
    largerTargets: largerTargets ?? this.largerTargets,
    lockEnabled: lockEnabled ?? this.lockEnabled,
    lockDelay: lockDelay ?? this.lockDelay,
    blockScreenshots: blockScreenshots ?? this.blockScreenshots,
    diagnosticsEnabled: diagnosticsEnabled ?? this.diagnosticsEnabled,
    diagnosticsLevel: diagnosticsLevel ?? this.diagnosticsLevel,
  );

  static const Object _keep = Object();

  /// Parses stored rows tolerantly: unknown or malformed values fall back to
  /// the defaults.
  factory AppSettings.fromRows(Map<String, String> rows) {
    T pick<T extends Enum>(List<T> values, String key, T fallback) {
      final raw = rows[key];
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    bool flag(String key) => rows[key] == '1';

    final tag = rows[SettingsKeys.locale];
    return AppSettings(
      loaded: true,
      themeMode: pick(ThemeMode.values, SettingsKeys.theme, ThemeMode.dark),
      localeTag: (tag == null || tag.isEmpty) ? null : tag,
      motion: pick(
        MotionPreference.values,
        SettingsKeys.motion,
        MotionPreference.system,
      ),
      highContrast: flag(SettingsKeys.highContrast),
      largerTargets: flag(SettingsKeys.largerTargets),
      lockEnabled: flag(SettingsKeys.lockEnabled),
      lockDelay: pick(
        LockDelay.values,
        SettingsKeys.lockDelay,
        LockDelay.immediately,
      ),
      blockScreenshots: flag(SettingsKeys.blockScreenshots),
      diagnosticsEnabled: flag(SettingsKeys.diagnosticsEnabled),
      diagnosticsLevel: pick(
        LogLevel.values,
        SettingsKeys.diagnosticsLevel,
        LogLevel.info,
      ),
    );
  }
}

/// Keys in `AppStateRows`. All values are non-secret.
abstract final class SettingsKeys {
  static const theme = 'settings.theme';
  static const locale = 'settings.locale';
  static const motion = 'settings.motion';
  static const highContrast = 'settings.high_contrast';
  static const largerTargets = 'settings.larger_targets';
  static const lockEnabled = 'settings.lock_enabled';
  static const lockDelay = 'settings.lock_delay';
  static const blockScreenshots = 'settings.block_screenshots';
  static const diagnosticsEnabled = 'settings.diagnostics_enabled';
  static const diagnosticsLevel = 'settings.diagnostics_level';
  static const consentCrashReports = 'consent.crash_reports';
  static const consentAnalytics = 'consent.analytics';
}
