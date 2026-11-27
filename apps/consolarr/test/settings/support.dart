// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/data/external_actions.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:observability/observability.dart';

/// A scripted platform authenticator.
class FakeDeviceAuthenticator implements DeviceAuthenticator {
  FakeDeviceAuthenticator({
    this.supportResult = DeviceAuthSupport.available,
    this.biometrics = true,
    List<DeviceAuthResult>? results,
  }) : results = results ?? [DeviceAuthResult.success];

  DeviceAuthSupport supportResult;
  bool biometrics;
  final List<DeviceAuthResult> results;
  final List<String> reasons = [];

  /// When set, `authenticate` waits for it (to keep a prompt open).
  Completer<DeviceAuthResult>? hold;

  @override
  Future<DeviceAuthSupport> support() async => supportResult;

  @override
  Future<bool> hasBiometrics() async => biometrics;

  @override
  Future<DeviceAuthResult> authenticate({required String reason}) async {
    reasons.add(reason);
    if (hold != null) return hold!.future;
    return results.length > 1 ? results.removeAt(0) : results.first;
  }
}

/// A clock the test moves by hand.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 1, 1, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// Records what reached the raw sinks.
class RecordingAnalytics implements Analytics {
  final List<String> events = [];
  final List<bool> enabledCalls = [];

  @override
  Future<void> setEnabled({required bool enabled}) async =>
      enabledCalls.add(enabled);

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async => events.add(name);
}

class RecordingCrashReporter implements CrashReporter {
  final List<Object> errors = [];
  final List<bool> enabledCalls = [];

  @override
  Future<void> setEnabled({required bool enabled}) async =>
      enabledCalls.add(enabled);

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async => errors.add(error);
}

/// The doubles every settings test shares.
class SettingsHarness {
  SettingsHarness({
    Map<String, String>? stored,
    FakeDeviceAuthenticator? auth,
    TestClock? clock,
    this.recordingSinks = true,
  }) : store = InMemorySettingsStore(stored),
       auth = auth ?? FakeDeviceAuthenticator(),
       clock = clock ?? TestClock();

  final InMemorySettingsStore store;
  final FakeDeviceAuthenticator auth;
  final TestClock clock;
  final RecordingSecureScreen secure = RecordingSecureScreen();
  final RecordingExternalActions actions = RecordingExternalActions();
  final RecordingAnalytics analytics = RecordingAnalytics();
  final RecordingCrashReporter crash = RecordingCrashReporter();

  /// Whether the raw analytics and crash sinks are replaced by recorders
  /// (false: the foss defaults, which are no-ops).
  final bool recordingSinks;

  List<Override> get overrides => [
    settingsStoreProvider.overrideWithValue(store),
    deviceAuthenticatorProvider.overrideWithValue(auth),
    clockProvider.overrideWithValue(clock.call),
    secureScreenProvider.overrideWithValue(secure),
    externalActionsProvider.overrideWithValue(actions),
    if (recordingSinks) rawAnalyticsProvider.overrideWithValue(analytics),
    if (recordingSinks) rawCrashReporterProvider.overrideWithValue(crash),
  ];

  /// A container with the first frame already marked done and the settings
  /// loaded (as after startup).
  Future<ProviderContainer> startedContainer() async {
    final c = ProviderContainer(overrides: overrides);
    c.read(firstFrameDoneProvider.notifier).markDone();
    c.read(settingsProvider);
    await settle(c);
    return c;
  }

  /// Lets pending microtasks (store reads) finish.
  Future<void> settle(ProviderContainer c) async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

Map<String, String> lockOn([LockDelay delay = LockDelay.immediately]) => {
  SettingsKeys.lockEnabled: '1',
  SettingsKeys.lockDelay: delay.name,
};
