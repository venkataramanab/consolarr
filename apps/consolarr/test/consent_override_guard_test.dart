// SPDX-License-Identifier: GPL-3.0-or-later

// Consent cannot be bypassed by plugging a sink in at the wrong place: the
// consent-gated `analyticsProvider` / `crashReporterProvider` must never be
// overridden by non-test code. An entry point (for example the Play flavor)
// replaces `rawAnalyticsProvider` / `rawCrashReporterProvider` instead, so the
// consent manager always sits in front of the SDK.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _gatedOverride = RegExp(
  r'(?<![A-Za-z0-9_])'
  r'(analyticsProvider|crashReporterProvider|'
  r'consentManagerProvider|consentStoreProvider|'
  // Everything that feeds, records or shares telemetry or diagnostics must
  // stay the app's own: a replaced tracker, logger, breadcrumb trail or log
  // would be a second, ungated way to collect.
  r'eventTrackerProvider|loggerProvider|breadcrumbsProvider|'
  r'diagnosticsLogProvider)'
  r'\s*\.\s*(overrideWith\w*|override\w*)',
);

/// The offending places in [source] (1-based `line: text`). The match runs
/// over the whole source, so whitespace and line breaks between the provider
/// and `.overrideWith` do not hide it.
List<String> gatedOverrides(String source) {
  return [
    for (final m in _gatedOverride.allMatches(source))
      '${'\n'.allMatches(source.substring(0, m.start)).length + 1}: '
          '${m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}',
  ];
}

/// Any use of the raw sinks. Only the files below may mention them.
final rawSinkReference = RegExp(r'raw(Analytics|CrashReporter)Provider');

/// The complete list of shipped files (under `apps/*/lib/`) that may name a
/// raw sink, with how many **lines** may do so. Keep it this short:
///  * `providers.dart`: the two definitions and the consent manager that
///    wraps them;
///  * `settings_providers.dart`: "is a reporting service plugged in" (the
///    privacy screen's wording), a read only;
///  * the Play entry point: the documented place to plug an SDK in (today
///    only its doc comment names them).
const rawSinkAllowlist = {
  'apps/consolarr/lib/src/providers.dart': 4,
  'apps/consolarr/lib/features/settings/application/settings_providers.dart': 2,
  'apps/consolarr_play/lib/main.dart': 1,
};

/// Lines of [source] that name a raw sink.
int rawSinkLines(String source) =>
    source.split('\n').where(rawSinkReference.hasMatch).length;

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

  test('the guard sees an override split across lines', () {
    for (final src in [
      'crashReporterProvider\n    .overrideWith((r) => c)',
      'analyticsProvider\n\t.\n  overrideWithValue(a)',
      'crashReporterProvider   \r\n  .overrideWithValue(c)',
    ]) {
      expect(gatedOverrides(src), hasLength(1), reason: src);
    }
    expect(
      gatedOverrides('a\nb\ncrashReporterProvider\n.overrideWith(x)').single,
      startsWith('3:'),
    );
    expect(
      gatedOverrides('rawCrashReporterProvider\n.overrideWithValue(c)'),
      isEmpty,
    );
  });

  test('the guard forbids overriding the consent manager and store', () {
    for (final src in [
      'consentManagerProvider.overrideWith((r) => m)',
      'consentManagerProvider\n    .overrideWithValue(m)',
      'consentStoreProvider.overrideWithValue(s)',
      'consentStoreProvider\n  .overrideWith((r) => s)',
    ]) {
      expect(gatedOverrides(src), hasLength(1), reason: src);
    }
    expect(gatedOverrides('ref.read(consentManagerProvider)'), isEmpty);
    expect(gatedOverrides('myconsentStoreProvider.overrideWith(x)'), isEmpty);
  });

  test('the guard covers the tracker, logger, breadcrumbs and log', () {
    for (final name in [
      'eventTrackerProvider',
      'loggerProvider',
      'breadcrumbsProvider',
      'diagnosticsLogProvider',
    ]) {
      expect(
        gatedOverrides('$name.overrideWithValue(x)'),
        hasLength(1),
        reason: name,
      );
      expect(gatedOverrides('$name\n  .overrideWith((r) => x)'), hasLength(1));
      expect(gatedOverrides('ref.watch($name)'), isEmpty);
    }
  });

  test('the raw-sink pattern finds every spelling', () {
    expect(rawSinkLines('rawAnalyticsProvider'), 1);
    expect(
      rawSinkLines('a(rawCrashReporterProvider)\nb\nrawAnalyticsProvider'),
      2,
    );
    expect(rawSinkLines('analyticsProvider and crashReporterProvider'), 0);
  });

  test('only the allow-listed files name a raw sink, within their limits', () {
    final root = _repoRoot();
    final seen = <String, int>{};
    final apps = Directory('${root.path}/apps');
    for (final f in apps.listSync(recursive: true, followLinks: false)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final rel = f.path.substring(root.path.length + 1);
      final segments = rel.split('/');
      // apps/<app>/lib/...: shipped code only.
      if (segments.length < 4 || segments[2] != 'lib') continue;
      final n = rawSinkLines(f.readAsStringSync());
      if (n > 0) seen[rel] = n;
    }
    for (final entry in seen.entries) {
      expect(
        rawSinkAllowlist,
        contains(entry.key),
        reason:
            '${entry.key} names a raw sink; plug sinks in only through the '
            'Play entry point',
      );
      expect(
        entry.value,
        lessThanOrEqualTo(rawSinkAllowlist[entry.key]!),
        reason: '${entry.key} uses a raw sink more than allowed',
      );
    }
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
