// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';

import 'support.dart';

void main() {
  test('both consents default to off and are stored as off', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    expect(c.read(consentProvider), ConsentState.none);
    expect(await c.read(consentStoreProvider).load(), ConsentState.none);
  });

  test(
    'with consent off zero calls reach analytics and the crash reporter',
    () async {
      final h = SettingsHarness();
      final c = await h.startedContainer();
      final tracker = c.read(eventTrackerProvider);
      await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
      await tracker.track(
        const ServerAddedEvent(serviceKind: ServiceKindParam.sonarr),
      );
      await c
          .read(crashReporterProvider)
          .recordError('boom', null, fatal: true);
      expect(h.analytics.events, isEmpty);
      expect(h.crash.errors, isEmpty);
      // Breadcrumbs are crash-report context: not even kept in memory while
      // crash consent is off.
      expect(c.read(breadcrumbsProvider).entries, isEmpty);
    },
  );

  test('switching analytics on forwards events; the toggle event itself is '
      'tracked', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    await c
        .read(consentProvider.notifier)
        .set(ConsentPurpose.analytics, enabled: true);
    expect(c.read(consentProvider).analytics, isTrue);
    expect(h.analytics.events, ['consent_changed']);
    await c
        .read(eventTrackerProvider)
        .track(const ScreenViewedEvent(screen: ScreenName.settings));
    expect(h.analytics.events, ['consent_changed', 'screen_viewed']);
    expect(h.crash.errors, isEmpty);
  });

  test('turning off stops collection at once and clears the trail', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    final n = c.read(consentProvider.notifier);
    await n.set(ConsentPurpose.analytics, enabled: true);
    await n.set(ConsentPurpose.crashReports, enabled: true);
    await c
        .read(eventTrackerProvider)
        .track(const ScreenViewedEvent(screen: ScreenName.settings));
    expect(c.read(breadcrumbsProvider).entries, isNotEmpty);

    final before = h.analytics.events.length;
    await n.set(ConsentPurpose.analytics, enabled: false);
    await n.set(ConsentPurpose.crashReports, enabled: false);
    expect(h.analytics.enabledCalls.last, isFalse);
    expect(h.crash.enabledCalls.last, isFalse);
    expect(c.read(breadcrumbsProvider).entries, isEmpty);

    await c
        .read(eventTrackerProvider)
        .track(const ScreenViewedEvent(screen: ScreenName.settings));
    await c.read(crashReporterProvider).recordError('x', null);
    // Withdrawing is itself not reported (analytics is off by then).
    expect(h.analytics.events.length, before);
    expect(h.crash.errors, isEmpty);
  });

  test('consent persists across restarts and is applied after load', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    await c
        .read(consentProvider.notifier)
        .set(ConsentPurpose.crashReports, enabled: true);
    expect(h.store.values[SettingsKeys.consentCrashReports], '1');
    expect(h.store.values[SettingsKeys.consentAnalytics], '0');

    final c2 = await h.startedContainer();
    c2.read(consentProvider);
    await h.settle(c2);
    expect(c2.read(consentProvider).crashReports, isTrue);
    expect(c2.read(consentProvider).analytics, isFalse);
    await c2.read(crashReporterProvider).recordError('after restart', null);
    expect(h.crash.errors.single, isA<CrashPayload>());
  });

  test('stored consent applies after the first frame without the Settings '
      'tab ever reading consentProvider', () async {
    final h = SettingsHarness(
      stored: {
        SettingsKeys.consentCrashReports: '1',
        SettingsKeys.consentAnalytics: '0',
      },
    );
    final c = ProviderContainer(overrides: h.overrides);
    addTearDown(c.dispose);
    // Before the first frame nothing is read and nothing is forwarded.
    await c.read(crashReporterProvider).recordError('early', null);
    expect(h.crash.errors, isEmpty);
    c.read(firstFrameDoneProvider.notifier).markDone();
    await h.settle(c);
    // Only the gated sink is read: consentProvider is never touched.
    await c.read(crashReporterProvider).recordError('after start', null);
    expect(h.crash.errors.single, isA<CrashPayload>());
    expect(h.crash.enabledCalls, contains(true));
    expect(h.analytics.enabledCalls, isNot(contains(true)));
  });

  test('settings and consent share one read of the settings table', () async {
    final store = FailingWriteSettingsStore({
      SettingsKeys.consentCrashReports: '1',
    });
    final h = SettingsHarness(store: store);
    final c = ProviderContainer(overrides: h.overrides);
    addTearDown(c.dispose);
    c.read(firstFrameDoneProvider.notifier).markDone();
    c.read(settingsProvider);
    c.read(crashReporterProvider);
    await h.settle(c);
    expect(c.read(settingsProvider).loaded, isTrue);
    expect(c.read(consentProvider).crashReports, isTrue);
    expect(store.readCalls, 1);
  });

  test('both consent keys are written in one call', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    await c
        .read(consentProvider.notifier)
        .set(ConsentPurpose.analytics, enabled: true);
    expect(h.store.values[SettingsKeys.consentAnalytics], '1');
    expect(h.store.values[SettingsKeys.consentCrashReports], '0');
    expect(h.store.writeAllCalls, 1);
  });

  test(
    'the foss build reports that no telemetry service is installed',
    () async {
      final c = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(telemetryAvailableProvider), isFalse);
    },
  );

  test('a build with a reporting service reports it as installed', () async {
    final h = SettingsHarness();
    final c = await h.startedContainer();
    expect(c.read(telemetryAvailableProvider), isTrue);
  });
}
