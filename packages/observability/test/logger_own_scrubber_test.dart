// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/observability.dart';
import 'package:test/test.dart';

import 'fake_tokens.dart';

/// A scrubber that lets everything through. Both classes are open to
/// subclassing, so the logger must not trust the ones it is handed.
class _NoOpScrubber extends DiagnosticsScrubber {
  const _NoOpScrubber();

  @override
  String scrub(String line) => line;
}

class _NoOpRedactor extends Redactor {
  const _NoOpRedactor();

  @override
  String redactText(String text) => text;
}

void main() {
  final canaries = <String>[
    fakeJwt(),
    fakeKeyed(List.filled(12, 'q').join()),
    fakeHex32,
    ['nas', 'canary', 'example'].join('.'),
  ];

  DiagnosticsLog newLog({List<String> known = const []}) => DiagnosticsLog(
    scrubber: DiagnosticsScrubber(knownValues: known),
  )
    ..enabled = true
    ..level = LogLevel.debug;

  test('a no-op scrubber and redactor on the logger cannot bypass the log', () {
    final log = newLog();
    final out = <String>[];
    final logger = AppLogger(
      sink: (_, m) => out.add(m),
      scrubber: const _NoOpScrubber(),
      redactor: const _NoOpRedactor(),
      diagnostics: log,
      minLevel: LogLevel.debug,
    );
    for (final c in canaries) {
      logger
        ..info('value $c here')
        ..error('failed', error: c);
    }
    expect(log.entries, hasLength(canaries.length * 2));
    for (final e in log.entries) {
      for (final c in canaries) {
        expect(e.message, isNot(contains(c)));
      }
    }
  });

  test('a known value is scrubbed in the log view at write time', () {
    final secret = List.filled(9, 'zq').join('x');
    final log = newLog(known: [secret]);
    // The logger has the default scrubber, which knows nothing of [secret].
    AppLogger(diagnostics: log, sink: (_, _) {}).info('server $secret ready');
    expect(log.entries.single.message, isNot(contains(secret)));
  });
}
