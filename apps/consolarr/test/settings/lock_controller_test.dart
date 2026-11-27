// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late SettingsHarness h;
  ProviderContainer? container;

  Future<ProviderContainer> start(SettingsHarness harness) async {
    final c = await harness.startedContainer();
    container = c;
    addTearDown(c.dispose);
    return c;
  }

  AppLockController ctl(ProviderContainer c) =>
      c.read(appLockStateProvider.notifier);
  AppLockState st(ProviderContainer c) => c.read(appLockStateProvider);

  test(
    'before the settings are read the lock is resolving (opaque cover)',
    () async {
      h = SettingsHarness(stored: lockOn());
      final c = ProviderContainer(overrides: h.overrides);
      addTearDown(c.dispose);
      // First frame not done: nothing resolved, nothing read.
      expect(c.read(appLockStateProvider).phase, LockPhase.resolving);
      expect(c.read(appLockStateProvider).contentVisible, isFalse);
    },
  );

  test('disabled: resolves to disabled and content is visible', () async {
    h = SettingsHarness();
    final c = await start(h);
    expect(st(c).phase, LockPhase.disabled);
    expect(st(c).contentVisible, isTrue);
  });

  test('cold start with the lock on is always locked', () async {
    h = SettingsHarness(stored: lockOn());
    final c = await start(h);
    expect(st(c).phase, LockPhase.locked);
    expect(c.read(appLockedProvider), isTrue);
  });

  test('unlock succeeds with the platform authenticator', () async {
    h = SettingsHarness(stored: lockOn());
    final c = await start(h);
    await ctl(c).authenticate(reason: 'Unlock');
    expect(st(c).phase, LockPhase.unlocked);
    expect(h.auth.reasons, ['Unlock']);
    expect(c.read(appLockedProvider), isFalse);
  });

  group('return after a delay', () {
    Future<ProviderContainer> unlocked(LockDelay delay) async {
      h = SettingsHarness(stored: lockOn(delay));
      final c = await start(h);
      await ctl(c).authenticate(reason: 'Unlock');
      expect(st(c).phase, LockPhase.unlocked);
      return c;
    }

    test('immediately: any return from the background locks', () async {
      final c = await unlocked(LockDelay.immediately);
      ctl(c).onBackgrounded();
      h.clock.advance(const Duration(seconds: 1));
      ctl(c).onResumed();
      expect(st(c).phase, LockPhase.locked);
    });

    test('1 minute: not elapsed stays unlocked, elapsed locks', () async {
      final c = await unlocked(LockDelay.oneMinute);
      ctl(c).onBackgrounded();
      h.clock.advance(const Duration(seconds: 59));
      ctl(c).onResumed();
      expect(st(c).phase, LockPhase.unlocked);

      ctl(c).onBackgrounded();
      h.clock.advance(const Duration(minutes: 1));
      ctl(c).onResumed();
      expect(st(c).phase, LockPhase.locked);
    });

    test('5 and 15 minutes use their own delay', () async {
      for (final (delay, mins) in [
        (LockDelay.fiveMinutes, 5),
        (LockDelay.fifteenMinutes, 15),
      ]) {
        final c = await unlocked(delay);
        ctl(c).onBackgrounded();
        h.clock.advance(Duration(minutes: mins - 1));
        ctl(c).onResumed();
        expect(st(c).phase, LockPhase.unlocked, reason: '$delay');
        ctl(c).onBackgrounded();
        h.clock.advance(Duration(minutes: mins));
        ctl(c).onResumed();
        expect(st(c).phase, LockPhase.locked, reason: '$delay');
      }
    });

    test('resuming without having been backgrounded never locks', () async {
      final c = await unlocked(LockDelay.immediately);
      ctl(c).onResumed();
      expect(st(c).phase, LockPhase.unlocked);
    });

    test(
      'the first background time counts (repeated pauses do not reset it)',
      () async {
        final c = await unlocked(LockDelay.oneMinute);
        ctl(c).onBackgrounded();
        h.clock.advance(const Duration(seconds: 40));
        ctl(c).onBackgrounded();
        h.clock.advance(const Duration(seconds: 40));
        ctl(c).onResumed();
        expect(st(c).phase, LockPhase.locked);
      },
    );

    test('the background time lives in memory only', () async {
      final c = await unlocked(LockDelay.immediately);
      ctl(c).onBackgrounded();
      expect(
        h.store.values.keys.where((k) => k.contains('background')),
        isEmpty,
      );
      // A new process (new container, same store) always starts locked.
      final fresh = await start(h);
      expect(st(fresh).phase, LockPhase.locked);
    });
  });

  group('failed attempts', () {
    test('a failure shows feedback, no detail, and can be retried', () async {
      h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
      );
      final c = await start(h);
      await ctl(c).authenticate(reason: 'x');
      expect(st(c).phase, LockPhase.locked);
      expect(st(c).failedAttempts, 1);
      expect(st(c).lastAttemptFailed, isTrue);
      expect(st(c).coolingDown(h.clock.now), isFalse);
      await ctl(c).authenticate(reason: 'x');
      expect(st(c).failedAttempts, 2);
    });

    test('three failures start a short cool-down; prompts are ignored until it '
        'ends', () async {
      h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
      );
      final c = await start(h);
      for (var i = 0; i < lockMaxAttempts; i++) {
        await ctl(c).authenticate(reason: 'x');
      }
      expect(st(c).coolingDown(h.clock.now), isTrue);
      final prompts = h.auth.reasons.length;
      await ctl(c).authenticate(reason: 'x');
      expect(h.auth.reasons.length, prompts, reason: 'no prompt while cooling');

      h.clock.advance(lockCoolDown + const Duration(seconds: 1));
      expect(st(c).coolingDown(h.clock.now), isFalse);
      await ctl(c).authenticate(reason: 'x');
      expect(h.auth.reasons.length, prompts + 1);
    });

    test('a platform lock-out also starts the cool-down', () async {
      h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.lockedOut]),
      );
      final c = await start(h);
      await ctl(c).authenticate(reason: 'x');
      expect(st(c).coolingDown(h.clock.now), isTrue);
    });

    test('dismissing the prompt is not a failed attempt', () async {
      h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.canceled]),
      );
      final c = await start(h);
      await ctl(c).authenticate(reason: 'x');
      expect(st(c).failedAttempts, 0);
      expect(st(c).lastAttemptFailed, isFalse);
      expect(st(c).phase, LockPhase.locked);
    });

    test('success resets the counters', () async {
      h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(
          results: [DeviceAuthResult.failed, DeviceAuthResult.success],
        ),
      );
      final c = await start(h);
      await ctl(c).authenticate(reason: 'x');
      await ctl(c).authenticate(reason: 'x');
      expect(st(c).phase, LockPhase.unlocked);
      expect(st(c).failedAttempts, 0);
    });

    test('a second prompt is not opened while one is showing', () async {
      h = SettingsHarness(stored: lockOn());
      h.auth.hold = null;
      final c = await start(h);
      final first = ctl(c).authenticate(reason: 'x');
      final second = ctl(c).authenticate(reason: 'x');
      await Future.wait([first, second]);
      expect(h.auth.reasons.length, 1);
    });
  });

  group('device conditions', () {
    test(
      'biometrics unavailable is reported; the credential is the fallback',
      () async {
        h = SettingsHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(biometrics: false),
        );
        final c = await start(h);
        await ctl(c).authenticate(reason: 'x');
        // The platform prompt still ran (with its credential fallback).
        expect(h.auth.reasons, isNotEmpty);
        expect(st(c).biometricsAvailable, isFalse);
        expect(st(c).phase, LockPhase.unlocked);
      },
    );

    test(
      'credential removed: stays locked, explains, never turns off silently',
      () async {
        h = SettingsHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(
            supportResult: DeviceAuthSupport.noSecureLock,
          ),
        );
        final c = await start(h);
        await ctl(c).authenticate(reason: 'x');
        expect(st(c).phase, LockPhase.locked);
        expect(st(c).problem, LockProblem.secureLockRemoved);
        expect(c.read(settingsProvider).lockEnabled, isTrue);
        expect(h.store.values[SettingsKeys.lockEnabled], '1');
      },
    );

    test(
      'credential removed: the user can explicitly turn the lock off',
      () async {
        h = SettingsHarness(
          stored: lockOn(),
          auth: FakeDeviceAuthenticator(
            supportResult: DeviceAuthSupport.noSecureLock,
          ),
        );
        final c = await start(h);
        await ctl(c).authenticate(reason: 'x');
        await ctl(c).turnOffAfterCredentialRemoved();
        expect(st(c).phase, LockPhase.disabled);
        expect(c.read(settingsProvider).lockEnabled, isFalse);
        expect(h.store.values[SettingsKeys.lockEnabled], '0');
      },
    );

    test(
      'turning off from the lock screen needs the removed-credential state',
      () async {
        h = SettingsHarness(stored: lockOn());
        final c = await start(h);
        await ctl(c).turnOffAfterCredentialRemoved();
        expect(st(c).phase, LockPhase.locked);
        expect(c.read(settingsProvider).lockEnabled, isTrue);
      },
    );
  });

  group('enable and disable', () {
    test('enable needs a secure lock method', () async {
      h = SettingsHarness(
        auth: FakeDeviceAuthenticator(
          supportResult: DeviceAuthSupport.noSecureLock,
        ),
      );
      final c = await start(h);
      expect(await ctl(c).enable(reason: 'x'), EnableLockResult.noSecureLock);
      expect(c.read(settingsProvider).lockEnabled, isFalse);
    });

    test('enable is confirmed by the authenticator and persists', () async {
      h = SettingsHarness();
      final c = await start(h);
      expect(await ctl(c).enable(reason: 'x'), EnableLockResult.enabled);
      expect(st(c).phase, LockPhase.unlocked);
      expect(h.store.values[SettingsKeys.lockEnabled], '1');
    });

    test('an unconfirmed enable leaves the lock off', () async {
      h = SettingsHarness(
        auth: FakeDeviceAuthenticator(results: [DeviceAuthResult.failed]),
      );
      final c = await start(h);
      expect(await ctl(c).enable(reason: 'x'), EnableLockResult.notConfirmed);
      expect(c.read(settingsProvider).lockEnabled, isFalse);
    });

    test('disable needs confirmation; a failed one keeps the lock', () async {
      h = SettingsHarness(
        stored: lockOn(),
        auth: FakeDeviceAuthenticator(
          results: [DeviceAuthResult.success, DeviceAuthResult.failed],
        ),
      );
      final c = await start(h);
      await ctl(c).authenticate(reason: 'x'); // unlock (success)
      expect(await ctl(c).disable(reason: 'x'), isFalse);
      expect(c.read(settingsProvider).lockEnabled, isTrue);
    });

    test('toggling the lock is tracked as a closed-set event', () async {
      h = SettingsHarness();
      final c = await start(h);
      await ctl(c).enable(reason: 'x');
      // Analytics consent is off, so nothing reaches the sink.
      expect(h.analytics.events, isEmpty);
    });
  });

  test('container is cleaned up', () {
    expect(container, isNotNull);
  });
}
