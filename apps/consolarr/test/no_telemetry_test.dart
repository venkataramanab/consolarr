// SPDX-License-Identifier: GPL-3.0-or-later

// The foss app (and every workspace package it depends on) must not depend
// on any telemetry / crash-reporting SDK. Those may only be added to
// apps/consolarr_play.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = RegExp(
  r'firebase|sentry|crashlytics|bugsnag|datadog|mixpanel|amplitude|appcenter|'
  r'posthog|segment|instabug|countly|matomo|google_analytics|'
  r'flutter_analytics|app_tracking|facebook_app_events|appsflyer|adjust_sdk|'
  r'branch_sdk|onesignal|clarity',
  caseSensitive: false,
);

Set<String> dependencyNames(File pubspec, {bool includeDev = false}) {
  final names = <String>{};
  String? section;
  for (final line in pubspec.readAsLinesSync()) {
    if (RegExp(r'^\S').hasMatch(line)) {
      final key = line.split(':').first;
      section =
          (key == 'dependencies' || (includeDev && key == 'dev_dependencies'))
          ? key
          : null;
      continue;
    }
    final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (section != null && m != null) names.add(m.group(1)!);
  }
  return names;
}

void main() {
  test(
    'foss app and its workspace packages have no telemetry dependencies',
    () {
      final root = Directory.current.parent.parent; // apps/consolarr -> repo
      final packages = {
        for (final d in Directory('${root.path}/packages').listSync())
          if (d is Directory) d.path.split('/').last: d,
      };
      final seen = <String>{};
      final queue = ['consolarr'];
      final offenders = <String>[];
      while (queue.isNotEmpty) {
        final name = queue.removeLast();
        if (!seen.add(name)) continue;
        final pubspec = name == 'consolarr'
            ? File('${Directory.current.path}/pubspec.yaml')
            : File('${packages[name]!.path}/pubspec.yaml');
        for (final dep in dependencyNames(pubspec, includeDev: true)) {
          if (_banned.hasMatch(dep)) offenders.add('$name -> $dep');
          if (packages.containsKey(dep)) queue.add(dep);
        }
      }
      expect(offenders, isEmpty);
      expect(seen, containsAll(['consolarr', 'design_system', 'l10n']));
    },
  );

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
