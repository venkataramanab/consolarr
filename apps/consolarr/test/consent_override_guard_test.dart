// SPDX-License-Identifier: GPL-3.0-or-later

// Consent cannot be bypassed by plugging a sink in at the wrong place: the
// consent-gated `analyticsProvider` / `crashReporterProvider` must never be
// overridden by non-test code. An entry point (for example the Play flavor)
// replaces `rawAnalyticsProvider` / `rawCrashReporterProvider` instead, so the
// consent manager always sits in front of the SDK.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _gatedOverride = RegExp(
  r'(?<![A-Za-z0-9_])(analyticsProvider|crashReporterProvider)\s*\.\s*'
  r'(overrideWith\w*|override\w*)',
);

/// The offending lines of [source] (1-based `line: text`).
List<String> gatedOverrides(String source) {
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_gatedOverride.hasMatch(lines[i])) '${i + 1}: ${lines[i].trim()}',
  ];
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/melos.yaml').existsSync() &&
      !Directory('${dir.path}/packages/observability').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('repository root not found');
    dir = parent;
  }
  return dir;
}

void main() {
  test('the guard recognises direct overrides and allows the raw seams', () {
    expect(
      gatedOverrides('analyticsProvider.overrideWithValue(a)'),
      hasLength(1),
    );
    expect(
      gatedOverrides('x = crashReporterProvider.overrideWith((r) => c);'),
      hasLength(1),
    );
    expect(
      gatedOverrides('rawAnalyticsProvider.overrideWithValue(a)'),
      isEmpty,
    );
    expect(
      gatedOverrides('rawCrashReporterProvider.overrideWithValue(c)'),
      isEmpty,
    );
    expect(gatedOverrides('ref.watch(analyticsProvider)'), isEmpty);
  });

  test('no non-test code overrides the consent-gated providers', () {
    final root = _repoRoot();
    final offenders = <String>[];
    for (final top in ['apps', 'packages']) {
      final dir = Directory('${root.path}/$top');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true, followLinks: false)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.substring(root.path.length + 1);
        final segments = rel.split('/');
        // Only shipped code: <project>/lib/... Tests, tools and generated
        // build output are not entry points.
        final libAt = segments.indexOf('lib');
        if (libAt < 0 || segments.contains('.dart_tool')) continue;
        for (final hit in gatedOverrides(f.readAsStringSync())) {
          offenders.add('$rel:$hit');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'override rawAnalyticsProvider / rawCrashReporterProvider instead',
    );
  });
}
