// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Where the lock is (SET-02).
enum LockPhase {
  /// The stored settings are not read yet: the first frame is an opaque cover.
  resolving,

  /// No lock configured.
  disabled,

  /// Content hidden until the device authenticator succeeds.
  locked,

  /// Unlocked; the app may lock again after the configured delay.
  unlocked,

  /// The stored settings could not be read (after a retry): fail closed. The
  /// content stays hidden and the window secure; the screen offers "try
  /// again". Never shows content.
  loadFailed,
}

/// Why a locked app cannot be unlocked right now.
enum LockProblem {
  /// The device's secure lock method was removed or is unusable.
  secureLockRemoved,
}

/// Attempts before the short cool-down starts.
const int lockMaxAttempts = 3;

/// How long the prompt is paused after [lockMaxAttempts] failures.
const Duration lockCoolDown = Duration(seconds: 30);

/// The state the lock screen shows. Carries no detail about why a credential
/// failed: only counts and the phase.
@immutable
class AppLockState {
  const AppLockState({
    this.phase = LockPhase.resolving,
    this.failedAttempts = 0,
    this.coolDownUntil,
    this.problem,
    this.authenticating = false,
    this.biometricsAvailable = true,
    this.lastAttemptFailed = false,
  });

  final LockPhase phase;

  /// Failed attempts since the last success or since the app locked.
  final int failedAttempts;

  /// While in the future **on the monotonic clock** (`monotonicClockProvider`),
  /// the unlock prompt is paused. A monotonic value, so changing the device
  /// clock can neither end nor extend the cool-down.
  final Duration? coolDownUntil;
  final LockProblem? problem;
  final bool authenticating;

  /// `false` shows "biometrics unavailable, use your device credential".
  final bool biometricsAvailable;

  /// The previous prompt ended in a failure (not a dismissal).
  final bool lastAttemptFailed;

  bool get locked => phase == LockPhase.locked;

  /// The app content may be shown.
  bool get contentVisible =>
      phase == LockPhase.disabled || phase == LockPhase.unlocked;

  /// [now] is the monotonic time.
  bool coolingDown(Duration now) =>
      coolDownUntil != null && now < coolDownUntil!;

  AppLockState copyWith({
    LockPhase? phase,
    int? failedAttempts,
    Object? coolDownUntil = _keep,
    Object? problem = _keep,
    bool? authenticating,
    bool? biometricsAvailable,
    bool? lastAttemptFailed,
  }) => AppLockState(
    phase: phase ?? this.phase,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    coolDownUntil: identical(coolDownUntil, _keep)
        ? this.coolDownUntil
        : coolDownUntil as Duration?,
    problem: identical(problem, _keep) ? this.problem : problem as LockProblem?,
    authenticating: authenticating ?? this.authenticating,
    biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
    lastAttemptFailed: lastAttemptFailed ?? this.lastAttemptFailed,
  );

  static const Object _keep = Object();
}

/// The lock state machine. Cold start always locks (when enabled); the
/// "backgrounded at" time is kept in memory only.
class AppLockController extends Notifier<AppLockState> {
  DateTime? _backgroundedAt;
  Duration? _backgroundedElapsed;

  DateTime Function() get _now => ref.read(clockProvider);
  Duration Function() get _mono => ref.read(monotonicClockProvider);

  /// Failed attempts survive a restart (non-secret, settings table). A stored
  /// count at the limit means a cool-down was running: it starts again, so
  /// killing the app is no shortcut.
  static const failedAttemptsKey = 'settings.lock_failed_attempts';

  AppLockState _restoreAttempts(AppLockState s) {
    if (s.phase != LockPhase.locked) return s;
    final stored = int.tryParse(
      ref.read(storedRowsProvider).value?[failedAttemptsKey] ?? '',
    );
    if (stored == null || stored <= 0) return s;
    if (stored >= lockMaxAttempts) {
      return s.copyWith(coolDownUntil: _mono() + lockCoolDown);
    }
    return s.copyWith(failedAttempts: stored);
  }

  void _persistAttempts(int value) {
    // Best effort: a failed write only loses the counter across a restart.
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(failedAttemptsKey, '$value')
          .catchError((Object _) {}),
    );
  }

  @override
  AppLockState build() {
    // Resolve once the stored settings have been applied (or failed to be
    // read); later changes of the switch come through the controller's own
    // methods.
    ref.listen<(bool, bool)>(
      settingsProvider.select((s) => (s.loaded, s.loadFailed)),
      (_, now) {
        final phase = state.phase;
        if (now.$1 && (phase == LockPhase.resolving)) _resolve();
      },
    );
    // Settings already applied (this provider is first read later): resolve
    // straight away.
    final settings = ref.read(settingsProvider);
    if (settings.loaded) {
      return _restoreAttempts(AppLockState(phase: _phaseFor(settings)));
    }
    return const AppLockState();
  }

  static LockPhase _phaseFor(AppSettings s) => s.loadFailed
      ? LockPhase.loadFailed
      : s.lockEnabled
      ? LockPhase.locked
      : LockPhase.disabled;

  void _resolve() {
    state = _restoreAttempts(
      state.copyWith(phase: _phaseFor(ref.read(settingsProvider))),
    );
  }

  /// "Try again" on the fail-closed screen: reads the settings again. The
  /// content stays hidden until they resolve.
  Future<void> retryLoad() async {
    if (state.phase != LockPhase.loadFailed) return;
    state = state.copyWith(phase: LockPhase.resolving);
    await ref.read(settingsProvider.notifier).reload();
  }

  /// The app left the foreground for good (`paused`/`hidden`). Both clocks
  /// are noted: the delay is measured on the monotonic one, so changing the
  /// wall clock cannot extend it.
  void onBackgrounded() {
    if (state.phase != LockPhase.unlocked || state.authenticating) return;
    _backgroundedAt ??= _now();
    _backgroundedElapsed ??= ref.read(monotonicClockProvider)();
  }

  /// The app is in the foreground again; locks when the delay has elapsed.
  void onResumed() {
    final since = _backgroundedAt;
    final sinceElapsed = _backgroundedElapsed;
    _backgroundedAt = null;
    _backgroundedElapsed = null;
    if (since == null || state.phase != LockPhase.unlocked) return;
    final settings = ref.read(settingsProvider);
    if (!settings.lockEnabled) return;
    // The longer absence on either clock counts: the monotonic clock cannot
    // be moved by the user, the wall clock also runs while the device sleeps.
    var away = _now().difference(since);
    if (sinceElapsed != null) {
      final mono = ref.read(monotonicClockProvider)() - sinceElapsed;
      if (mono > away) away = mono;
    }
    if (settings.lockDelay == LockDelay.immediately ||
        away >= settings.lockDelay.duration) {
      state = state.copyWith(
        phase: LockPhase.locked,
        failedAttempts: 0,
        coolDownUntil: null,
        lastAttemptFailed: false,
      );
    }
  }

  /// Shows the system prompt. Safe to call repeatedly: ignored while a prompt
  /// is open, while cooling down and when not locked.
  Future<void> authenticate({required String reason}) async {
    if (state.phase != LockPhase.locked || state.authenticating) return;
    if (state.coolingDown(_mono())) return;
    final auth = ref.read(deviceAuthenticatorProvider);
    state = state.copyWith(authenticating: true, lastAttemptFailed: false);
    try {
      final support = await auth.support();
      if (!ref.mounted) return;
      switch (support) {
        case DeviceAuthSupport.noSecureLock:
          state = state.copyWith(
            authenticating: false,
            problem: LockProblem.secureLockRemoved,
          );
          return;
        case DeviceAuthSupport.indeterminate:
          // The platform could not be asked: retryable, never "removed".
          state = state.copyWith(authenticating: false);
          return;
        case DeviceAuthSupport.available:
          break;
      }
      final biometrics = await auth.hasBiometrics();
      if (!ref.mounted) return;
      final result = await auth.authenticate(reason: reason);
      if (!ref.mounted) return;
      _apply(result, biometrics: biometrics);
    } on Object {
      // A platform error is "could not ask": still locked, retryable.
      if (ref.mounted) state = state.copyWith(authenticating: false);
    }
  }

  void _apply(DeviceAuthResult result, {required bool biometrics}) {
    final failedBefore =
        state.failedAttempts + (state.coolDownUntil == null ? 0 : 1);
    switch (result) {
      case DeviceAuthResult.success:
        state = state.copyWith(
          phase: LockPhase.unlocked,
          authenticating: false,
          failedAttempts: 0,
          coolDownUntil: null,
          problem: null,
          biometricsAvailable: biometrics,
          lastAttemptFailed: false,
        );
        if (failedBefore > 0) _persistAttempts(0);
      case DeviceAuthResult.canceled:
        state = state.copyWith(
          authenticating: false,
          biometricsAvailable: biometrics,
        );
      case DeviceAuthResult.failed:
      case DeviceAuthResult.lockedOut:
        final failures = state.failedAttempts + 1;
        final coolDown =
            result == DeviceAuthResult.lockedOut || failures >= lockMaxAttempts;
        state = state.copyWith(
          authenticating: false,
          failedAttempts: coolDown ? 0 : failures,
          coolDownUntil: coolDown ? _mono() + lockCoolDown : null,
          biometricsAvailable: biometrics,
          lastAttemptFailed: true,
        );
        _persistAttempts(coolDown ? lockMaxAttempts : failures);
      case DeviceAuthResult.noCredential:
        state = state.copyWith(
          authenticating: false,
          problem: LockProblem.secureLockRemoved,
        );
    }
  }

  /// Runs a system prompt for a settings action with the `authenticating`
  /// flag set, so the device-credential activity pausing the app is not taken
  /// for the user leaving (which would re-lock mid-confirmation).
  Future<DeviceAuthResult> _confirm(String reason) async {
    state = state.copyWith(authenticating: true);
    try {
      return await ref
          .read(deviceAuthenticatorProvider)
          .authenticate(reason: reason);
    } finally {
      if (ref.mounted) state = state.copyWith(authenticating: false);
    }
  }

  /// Switches the lock on after the device authenticator confirmed. Returns
  /// `false` (lock stays off) when the device has no secure lock method or the
  /// confirmation failed.
  Future<EnableLockResult> enable({required String reason}) async {
    final auth = ref.read(deviceAuthenticatorProvider);
    switch (await auth.support()) {
      case DeviceAuthSupport.noSecureLock:
        return EnableLockResult.noSecureLock;
      case DeviceAuthSupport.indeterminate:
        return EnableLockResult.notConfirmed;
      case DeviceAuthSupport.available:
        break;
    }
    final result = await _confirm(reason);
    if (!ref.mounted || result != DeviceAuthResult.success) {
      return EnableLockResult.notConfirmed;
    }
    final stored = await ref
        .read(settingsProvider.notifier)
        .setLockEnabled(true);
    if (!stored) return EnableLockResult.notConfirmed;
    state = const AppLockState(phase: LockPhase.unlocked);
    await _track(enabled: true);
    return EnableLockResult.enabled;
  }

  /// Switches the lock off after the device authenticator confirmed.
  Future<bool> disable({required String reason}) async {
    if (state.authenticating) return false;
    final result = await _confirm(reason);
    if (!ref.mounted || result != DeviceAuthResult.success) return false;
    return _turnOff();
  }

  /// For a lock whose device credential was removed: the user explicitly turns
  /// the lock off from the lock screen (never done silently). The platform is
  /// asked again first and the lock goes off only if it **really answers**
  /// that no secure lock method exists; an error or a credential that is back
  /// never turns it off.
  Future<void> turnOffAfterCredentialRemoved() async {
    if (state.problem != LockProblem.secureLockRemoved ||
        state.authenticating) {
      return;
    }
    final support = await ref.read(deviceAuthenticatorProvider).support();
    if (!ref.mounted) return;
    switch (support) {
      case DeviceAuthSupport.noSecureLock:
        await _turnOff();
      case DeviceAuthSupport.available:
        // The credential is back: a normal unlock again.
        state = state.copyWith(problem: null);
      case DeviceAuthSupport.indeterminate:
        break;
    }
  }

  Future<bool> _turnOff() async {
    final stored = await ref
        .read(settingsProvider.notifier)
        .setLockEnabled(false);
    if (!stored || !ref.mounted) return false;
    state = const AppLockState(phase: LockPhase.disabled);
    await _track(enabled: false);
    return true;
  }

  Future<void> _track({required bool enabled}) => ref
      .read(eventTrackerProvider)
      .track(SettingsAppLockToggledEvent(enabled: enabled));
}

enum EnableLockResult { enabled, noSecureLock, notConfirmed }

final appLockStateProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// Whether the app content is hidden behind the lock. Polling and other
/// background work watches this and pauses.
final appLockedProvider = Provider<bool>(
  (ref) => !ref.watch(appLockStateProvider.select((s) => s.contentVisible)),
);
