// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/observability.dart';
import 'package:test/test.dart';

/// Values that must never reach an event, breadcrumb or log line.
const _hostile = [
  'https://admin:hunter2@nas.example:8989/sonarr/api?apikey=0123456789abcdef0123456789abcdef',
  'nas.private.example',
  '192.0.2.77',
  'alice-the-admin',
  'Example Show S01E01 1080p',
  '0123456789abcdef0123456789abcdef',
  'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl',
  'hunter2',
];

class _Recording implements Analytics {
  final List<String> lines = [];
  bool enabled = true;
  @override
  Future<void> setEnabled({required bool enabled}) async =>
      this.enabled = enabled;
  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async {
    if (enabled) lines.add('$name $parameters');
  }
}

void _expectClean(Iterable<String> lines) {
  final text = lines.join('\n');
  for (final h in _hostile) {
    expect(text, isNot(contains(h)), reason: 'leaked $h');
  }
}

void main() {
  test(
    'every event/breadcrumb combination is free of hostile values',
    () async {
      final a = _Recording();
      final crumbs = Breadcrumbs();
      final t = EventTracker(analytics: a, breadcrumbs: crumbs);
      for (final s in ScreenName.values) {
        await t.track(ScreenViewedEvent(screen: s));
      }
      for (final k in ServiceKindParam.values) {
        await t.track(ServerAddedEvent(serviceKind: k));
        for (final c in ErrorCategoryParam.values) {
          await t.track(
            ConnectionTestResultEvent(
              serviceKind: k,
              errorCategory: c,
              majorVersion: 4,
            ),
          );
        }
      }
      for (final d in CertificateDecisionParam.values) {
        await t.track(CertificateDecisionEvent(decision: d));
      }
      _expectClean(a.lines);
      _expectClean(crumbs.entries.map((c) => c.line));
      expect(a.lines, isNotEmpty);
      expect(crumbs.entries, isNotEmpty);
    },
  );

  test('tracker records navigation and API error breadcrumbs', () async {
    final crumbs = Breadcrumbs();
    final t = EventTracker(analytics: _Recording(), breadcrumbs: crumbs);
    await t.track(const ScreenViewedEvent(screen: ScreenName.serverEditor));
    await t.track(
      const ConnectionTestResultEvent(
        serviceKind: ServiceKindParam.sonarr,
        errorCategory: ErrorCategoryParam.authFailed,
      ),
    );
    await t.track(
      const ConnectionTestResultEvent(serviceKind: ServiceKindParam.sonarr),
    );
    expect(crumbs.entries.map((c) => c.line), [
      'nav server_editor',
      'api_error auth_failed sonarr',
    ]);
  });

  test('breadcrumbs are a bounded ring buffer', () {
    final crumbs = Breadcrumbs(capacity: 3);
    for (var i = 0; i < 10; i++) {
      crumbs.add(Breadcrumb.navigation(ScreenName.values[i % 3]));
    }
    expect(crumbs.entries, hasLength(3));
    expect(Breadcrumbs().capacity, 50);
    crumbs.clear();
    expect(crumbs.entries, isEmpty);
  });

  test('analytics that is disabled records nothing', () async {
    final a = _Recording()..enabled = false;
    final t = EventTracker(analytics: a, breadcrumbs: Breadcrumbs());
    await t.track(const ScreenViewedEvent(screen: ScreenName.shell));
    expect(a.lines, isEmpty);
    // The no-op default accepts events without effect or error.
    await EventTracker(
      analytics: const NoopAnalytics(),
      breadcrumbs: Breadcrumbs(),
    ).track(const ScreenViewedEvent(screen: ScreenName.shell));
  });

  test('logger redacts hostile values placed in messages and errors', () {
    final out = <String>[];
    final log = AppLogger(sink: (_, m) => out.add(m), minLevel: LogLevel.debug);
    for (final h in _hostile.take(1)) {
      log
        ..info('request to $h failed')
        ..error('boom', error: 'url=$h')
        ..warning('apikey=$h');
    }
    log.info('Authorization: Bearer ${_hostile[5]}');
    log.info('token=${_hostile[6]} password=${_hostile.last}');
    final text = out.join('\n');
    for (final secret in [
      'hunter2',
      '0123456789abcdef0123456789abcdef',
      'eyJhbGciOiJIUzI1NiJ9',
    ]) {
      expect(text, isNot(contains(secret)));
    }
  });
}
