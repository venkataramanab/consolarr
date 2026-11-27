// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/observability.dart';
import 'package:test/test.dart';

class _Analytics implements Analytics {
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

class _Crash implements CrashReporter {
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

void main() {
  late _Analytics analytics;
  late _Crash crash;
  late Breadcrumbs crumbs;
  late InMemoryConsentStore store;
  late ConsentManager manager;
  late EventTracker tracker;

  setUp(() {
    analytics = _Analytics();
    crash = _Crash();
    crumbs = Breadcrumbs();
    store = InMemoryConsentStore();
    manager = ConsentManager(
      store: store,
      analytics: analytics,
      crashReporter: crash,
      breadcrumbs: crumbs,
    );
    tracker = EventTracker(analytics: manager.analytics, breadcrumbs: crumbs);
  });

  test('defaults are off and persist nothing until changed', () async {
    expect(manager.state, ConsentState.none);
    await manager.load();
    expect(manager.state, ConsentState.none);
  });

  test('with consent off zero calls reach analytics or the crash reporter',
      () async {
    await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
    await manager.crashReporter.recordError('x', null);
    await manager.crashReporter.recordError('y', null, fatal: true);
    expect(analytics.events, isEmpty);
    expect(crash.errors, isEmpty);
    // Breadcrumbs stay local.
    expect(crumbs.entries, isNotEmpty);
  });

  test('analytics consent forwards events but not errors', () async {
    await manager.set(ConsentPurpose.analytics, enabled: true);
    await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
    await manager.crashReporter.recordError('x', null);
    expect(analytics.events, ['screen_viewed']);
    expect(crash.errors, isEmpty);
  });

  test('crash consent forwards errors but not events', () async {
    await manager.set(ConsentPurpose.crashReports, enabled: true);
    await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
    await manager.crashReporter.recordError('x', null);
    expect(analytics.events, isEmpty);
    expect(crash.errors, ['x']);
  });

  test('turning a toggle off stops collection at once and clears queued data',
      () async {
    await manager.set(ConsentPurpose.crashReports, enabled: true);
    await manager.set(ConsentPurpose.analytics, enabled: true);
    await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
    expect(crumbs.entries, isNotEmpty);

    await manager.set(ConsentPurpose.crashReports, enabled: false);
    expect(crash.enabledCalls.last, isFalse);
    expect(crumbs.entries, isEmpty, reason: 'crash trail cleared');
    await manager.crashReporter.recordError('after', null);
    expect(crash.errors, isEmpty);

    await manager.set(ConsentPurpose.analytics, enabled: false);
    expect(analytics.enabledCalls.last, isFalse);
    final before = analytics.events.length;
    await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
    expect(analytics.events.length, before);
  });

  test('state persists and is restored on load', () async {
    await manager.set(ConsentPurpose.analytics, enabled: true);
    expect(await store.load(), const ConsentState(analytics: true));
    final other = ConsentManager(
      store: store,
      analytics: analytics,
      crashReporter: crash,
      breadcrumbs: crumbs,
    );
    await other.load();
    expect(other.state.analytics, isTrue);
    expect(other.state.crashReports, isFalse);
  });

  test('notifies listeners when the state changes', () async {
    var n = 0;
    manager.addListener(() => n++);
    await manager.set(ConsentPurpose.analytics, enabled: true);
    await manager.set(ConsentPurpose.analytics, enabled: true);
    expect(n, 1);
  });

  test('the loaded state is applied to the sinks without a toggle', () async {
    await store.save(const ConsentState(analytics: true));
    await manager.load();
    await tracker.track(const ScreenViewedEvent(screen: ScreenName.settings));
    expect(analytics.events, ['screen_viewed']);
  });
}
