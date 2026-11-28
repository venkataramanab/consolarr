// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Every `AppError.debugDetail` the code can produce, found in the sources
/// (interpolations are replaced by a sample) plus the shared constants.
Set<String> _details() {
  final out = <String>{
    delugeNoHostDetail,
    transmissionHostNotAllowedDetail,
    needsCredentialsDetail,
  };
  final literal = RegExp(r"debugDetail:\s*'([^']*)'");
  for (final root in ['lib', '../../packages']) {
    for (final f in Directory(root).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/test/') || f.path.contains('.dart_tool')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        out.add(m.group(1)!.replaceAll(RegExp(r'\$\w+|\$\{[^}]*\}'), 'x'));
      }
    }
  }
  return out;
}

void main() {
  const scrubber = DiagnosticsScrubber();

  test('the sources contain the details this test is meant to cover', () {
    expect(_details().length, greaterThan(15));
  });

  test('every debugDetail passes the scrub: stable, idempotent, no leak', () {
    for (final d in _details()) {
      final once = scrubber.scrub(d);
      expect(scrubber.scrub(once), once, reason: d);
      expect(const Redactor().redactText(d), d, reason: 'redactor changed $d');
      // A detail must not need scrubbing: it is secret-free by contract.
      expect(once, d, reason: 'scrub changed "$d"');
    }
  });

  test('a detail with a secret appended is still cleaned', () {
    for (final d in _details()) {
      final out = scrubber.scrub('$d password=canarypw123 at 198.51.100.9');
      expect(out, isNot(contains('canarypw123')), reason: d);
      expect(out, isNot(contains('198.51.100.9')), reason: d);
    }
  });
}
