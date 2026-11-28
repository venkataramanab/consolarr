// SPDX-License-Identifier: GPL-3.0-or-later

// `Analytics.logEvent(String, Map)` is the sink interface (an SDK adapter
// implements it). Shipped code must never call it with a hand-built name or
// parameters: events go through `EventTracker.track(AppEvent)`, whose events
// are generated from the catalog (closed enums, ints, bools). Only the
// tracker and the consent gate may call `logEvent`.

import 'dart:io';

import 'package:test/test.dart';

/// A call, not a declaration: `x.logEvent(` or `x?.logEvent(`.
final logEventCall = RegExp(r'[A-Za-z0-9_)\]]\s*\??\.\s*logEvent\s*\(');

const _allowed = {
  'packages/observability/lib/src/event_tracker.dart',
  'packages/observability/lib/src/consent_gating.dart',
};

void main() {
  test('the pattern finds calls and ignores declarations', () {
    expect(logEventCall.hasMatch('analytics.logEvent("x")'), isTrue);
    expect(logEventCall.hasMatch('ref.read(a).logEvent("x")'), isTrue);
    expect(logEventCall.hasMatch('a\n  .logEvent(\n"x")'), isTrue);
    expect(
      logEventCall.hasMatch('Future<void> logEvent(String n) async {}'),
      isFalse,
    );
    expect(logEventCall.hasMatch('/// Logs an event.'), isFalse);
  });

  test('only the tracker and the consent gate call logEvent', () {
    final root = Directory('../..').absolute;
    final offenders = <String>[];
    for (final top in ['apps', 'packages']) {
      for (final f in Directory(
        '${root.path}/$top',
      ).listSync(recursive: true, followLinks: false)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final rel = f.path.substring(root.path.length + 1);
        final seg = rel.split('/');
        if (seg.length < 4 || seg[2] != 'lib') continue; // shipped code only
        if (_allowed.contains(rel)) continue;
        if (logEventCall.hasMatch(f.readAsStringSync())) offenders.add(rel);
      }
    }
    expect(offenders, isEmpty, reason: 'use EventTracker.track(AppEvent)');
  });
}
