// SPDX-License-Identifier: GPL-3.0-or-later

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

  /// While in the future, the unlock prompt is paused.
  final DateTime? coolDownUntil;
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

  bool coolingDown(DateTime now) =>
      coolDownUntil != null && now.isBefore(coolDownUntil!);

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
        : coolDownUntil as DateTime?,
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

  DateTime Function() get _now => ref.read(clockProvider);

  @override
  AppLockState build() {
    // Resolve once the stored settings have been applied; later changes of
    // the switch come through the controller's own methods.
    ref.listen<bool>(settingsProvider.select((s) => s.loaded), (_, loaded) {
      if (loaded && state.phase == LockPhase.resolving) _resolve();
    });
    // Settings already applied (this provider is first read later): resolve
    // straight away.
    final settings = ref.read(settingsProvider);
    if (settings.loaded) {
      return AppLockState(
        phase: settings.lockEnabled ? LockPhase.locked : LockPhase.disabled,
      );
    }
    return const AppLockState();
  }

  void _resolve() {
    final enabled = ref.read(settingsProvider).lockEnabled;
    state = state.copyWith(
      phase: enabled ? LockPhase.locked : LockPhase.disabled,
    );
  }

  /// The app left the foreground for good (`paused`/`hidden`).
  void onBackgrounded() {
    if (state.phase != LockPhase.unlocked || state.authenticating) return;
    _backgroundedAt ??= _now();
  }

  /// The app is in the foreground again; locks when the delay has elapsed.
  void onResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || state.phase != LockPhase.unlocked) return;
    final settings = ref.read(settingsProvider);
    if (!settings.lockEnabled) return;
    final away = _now().difference(since);
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
    if (state.coolingDown(_now())) return;
    final auth = ref.read(deviceAuthenticatorProvider);
    state = state.copyWith(authenticating: true, lastAttemptFailed: false);
    final support = await auth.support();
    if (!ref.mounted) return;
    if (support == DeviceAuthSupport.noSecureLock) {
      state = state.copyWith(
        authenticating: false,
        problem: LockProblem.secureLockRemoved,
      );
      return;
    }
    final biometrics = await auth.hasBiometrics();
    if (!ref.mounted) return;
    final result = await auth.authenticate(reason: reason);
    if (!ref.mounted) return;
    _apply(result, biometrics: biometrics);
  }

  void _apply(DeviceAuthResult result, {required bool biometrics}) {
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
          coolDownUntil: coolDown ? _now().add(lockCoolDown) : null,
          biometricsAvailable: biometrics,
          lastAttemptFailed: true,
        );
      case DeviceAuthResult.unavailable:
        state = state.copyWith(
          authenticating: false,
          problem: LockProblem.secureLockRemoved,
        );
    }
  }

  /// Switches the lock on after the device authenticator confirmed. Returns
  /// `false` (lock stays off) when the device has no secure lock method or the
  /// confirmation failed.
  Future<EnableLockResult> enable({required String reason}) async {
    final auth = ref.read(deviceAuthenticatorProvider);
    if (await auth.support() == DeviceAuthSupport.noSecureLock) {
      return EnableLockResult.noSecureLock;
    }
    final result = await auth.authenticate(reason: reason);
    if (result != DeviceAuthResult.success)
      return EnableLockResult.notConfirmed;
    await ref.read(settingsProvider.notifier).setLockEnabled(true);
    state = const AppLockState(phase: LockPhase.unlocked);
    await _track(enabled: true);
    return EnableLockResult.enabled;
  }

  /// Switches the lock off after the device authenticator confirmed.
  Future<bool> disable({required String reason}) async {
    final auth = ref.read(deviceAuthenticatorProvider);
    final result = await auth.authenticate(reason: reason);
    if (result != DeviceAuthResult.success) return false;
    await _turnOff();
    return true;
  }

  /// For a lock whose device credential was removed: the user explicitly turns
  /// the lock off from the lock screen (never done silently).
  Future<void> turnOffAfterCredentialRemoved() async {
    if (state.problem != LockProblem.secureLockRemoved) return;
    await _turnOff();
  }

  Future<void> _turnOff() async {
    await ref.read(settingsProvider.notifier).setLockEnabled(false);
    state = const AppLockState(phase: LockPhase.disabled);
    await _track(enabled: false);
  }

  Future<void> _track({required bool enabled}) => ref
      .read(eventTrackerProvider)
      .track(AppLockToggledEvent(enabled: enabled));
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
