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
  r'branch_sdk|onesignal|clarity',
  caseSensitive: false,
);

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
    if (_banned.hasMatch(name)) name,
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
    ]) {
      expect(_banned.hasMatch(n), isTrue, reason: n);
    }
    expect(_banned.hasMatch('go_router'), isFalse);
  });
}
