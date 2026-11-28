// SPDX-License-Identifier: GPL-3.0-or-later

// The foss app must not depend, directly or transitively, on any telemetry /
// crash-reporting SDK. Those may only be added to apps/consolarr_play. The
// check walks the resolved graph from `dart pub deps --json`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = RegExp(
  r'firebase|sentry|crashlytics|bugsnag|datadog|mixpanel|amplitude|appcenter|'
  r'posthog|segment|instabug|countly|matomo|google_analytics|'
  r'flutter_analytics|app_tracking|facebook_app_events|appsflyer|adjust_sdk|'
  r'branch_sdk|onesignal|clarity|'
  // Advertising, Google services and install attribution.
  r'admob|play_services|install_referrer|advertising_id|'
  // More crash, performance and behaviour analytics SDKs.
  r'appmetrica|newrelic|embrace|rollbar|raygun|flurry|smartlook|uxcam|hotjar',
  caseSensitive: false,
);

/// Short words that would match inside ordinary names (`threads`, `loads`) if
/// searched as substrings: matched as whole `_`-separated words instead
/// (`google_mobile_ads`, `flutter_gms`, `ads_core`).
final _bannedWords = RegExp(r'^(ads?|gms)$', caseSensitive: false);

/// Whether a package [name] is (or looks like) a telemetry, advertising or
/// attribution SDK.
bool isBannedPackage(String name) =>
    _banned.hasMatch(name) || name.split('_').any(_bannedWords.hasMatch);

/// The only telemetry-like packages `apps/consolarr_play` may bring in. Empty:
/// no SDK is linked yet. Adding one is a deliberate edit of this set (and a
/// review), never an accident.
const Set<String> playTelemetryAllowlist = {};

/// Names reachable from [root] in a `dart pub deps --json` style [packages]
/// list (each entry has `name` and `dependencies`), including [root].
Set<String> dependencyClosure(List<Object?> packages, String root) {
  final graph = {
    for (final p in packages.cast<Map<String, Object?>>())
      p['name']! as String: [
        ...?(p['dependencies'] as List<Object?>?)?.cast<String>(),
      ],
  };
  final seen = <String>{};
  final queue = [root];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (!seen.add(name)) continue;
    queue.addAll(graph[name] ?? const []);
  }
  return seen;
}

/// Banned packages in the closure of [root], as `name` strings.
List<String> telemetryOffenders(List<Object?> packages, String root) => [
  for (final name in dependencyClosure(packages, root))
    if (isBannedPackage(name)) name,
]..sort();

List<Object?> resolvedPackages() {
  final result = Process.runSync('dart', [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail('dart pub deps --json failed:\n${result.stderr}');
  }
  final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
  return json['packages']! as List<Object?>;
}

void main() {
  test('resolved dependency graph of the foss app has no telemetry', () {
    // The full resolved graph (direct and transitive, dev included), not just
    // the pubspec's direct dependencies: a telemetry SDK pulled in by another
    // package must fail too.
    final packages = resolvedPackages();
    final closure = dependencyClosure(packages, 'consolarr');
    expect(
      closure,
      containsAll(['consolarr', 'design_system', 'l10n', 'flutter', 'dio']),
      reason: 'closure traversal must reach transitive packages',
    );
    expect(telemetryOffenders(packages, 'consolarr'), isEmpty);
  });

  test('a transitive telemetry dependency is detected', () {
    final graph = <Object?>[
      {
        'name': 'app',
        'dependencies': ['lib_a'],
      },
      {
        'name': 'lib_a',
        'dependencies': ['lib_b'],
      },
      {
        'name': 'lib_b',
        'dependencies': ['firebase_core'],
      },
      {'name': 'firebase_core', 'dependencies': <String>[]},
      {
        'name': 'other_app',
        'dependencies': ['sentry_flutter'],
      },
      {'name': 'sentry_flutter', 'dependencies': <String>[]},
    ];
    expect(telemetryOffenders(graph, 'app'), ['firebase_core']);
    expect(telemetryOffenders(graph, 'other_app'), ['sentry_flutter']);
    expect(telemetryOffenders(graph, 'lib_a'), ['firebase_core']);
  });

  test('banned-name matcher catches the usual suspects', () {
    for (final n in [
      'firebase_core',
      'sentry_flutter',
      'firebase_crashlytics',
      'mixpanel_flutter',
      // The widened list.
      'google_mobile_ads',
      'admob_flutter',
      'ads_core',
      'flutter_gms',
      'google_play_services_foo',
      'play_install_referrer',
      'advertising_id',
      'appmetrica_plugin',
      'newrelic_mobile',
      'embrace',
      'rollbar_flutter',
      'raygun4flutter',
      'flurry_sdk',
      'smartlook',
      'flutter_uxcam',
      'hotjar_flutter',
    ]) {
      expect(isBannedPackage(n), isTrue, reason: n);
    }
    for (final n in [
      'go_router',
      'threads_helper',
      'downloads',
      'riverpod',
      'dio',
      'adaptive_x',
      'gmsx',
    ]) {
      expect(isBannedPackage(n), isFalse, reason: n);
    }
  });

  test('a planted ads package two levels down is found', () {
    final graph = <Object?>[
      {
        'name': 'app',
        'dependencies': ['lib_a'],
      },
      {
        'name': 'lib_a',
        'dependencies': ['google_mobile_ads'],
      },
      {'name': 'google_mobile_ads', 'dependencies': <String>[]},
    ];
    expect(telemetryOffenders(graph, 'app'), ['google_mobile_ads']);
  });

  test('the Play app links no telemetry SDK (explicit, empty allowlist)', () {
    final packages = resolvedPackages();
    final closure = dependencyClosure(packages, 'consolarr_play');
    expect(
      closure,
      containsAll(['consolarr_play', 'consolarr', 'observability']),
      reason: 'closure traversal must reach transitive packages',
    );
    final offenders = [
      for (final p in telemetryOffenders(packages, 'consolarr_play'))
        if (!playTelemetryAllowlist.contains(p)) p,
    ];
    expect(offenders, isEmpty);
  });

  test('the lock file of the whole workspace has no such package', () {
    var dir = Directory.current.absolute;
    while (!File('${dir.path}/pubspec.lock').existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) fail('pubspec.lock not found');
      dir = parent;
    }
    final names = [
      for (final m in RegExp(
        r'^  ([a-z0-9_]+):\n    dependency:',
        multiLine: true,
      ).allMatches(File('${dir.path}/pubspec.lock').readAsStringSync()))
        m.group(1)!,
    ];
    expect(names, containsAll(['dio', 'flutter_riverpod']));
    expect([
      for (final n in names)
        if (isBannedPackage(n) && !playTelemetryAllowlist.contains(n)) n,
    ], isEmpty);
  });
}
