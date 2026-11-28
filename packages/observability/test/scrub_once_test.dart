// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/observability.dart';
import 'package:test/test.dart';

class _Counting extends DiagnosticsScrubber {
  int calls = 0;

  @override
  String scrub(String line) {
    calls++;
    return super.scrub(line);
  }
}

// Assembled at runtime so no key-shaped literal sits in the repository.
String _keyed() => ['api', 'key=', 'canary', '12345678'].join();

void main() {
  test('a logged line is scrubbed once, however many sinks it reaches', () {
    final scrubber = _Counting();
    final log = DiagnosticsLog(scrubber: scrubber)
      ..enabled = true
      ..level = LogLevel.debug;
    final out = <String>[];
    AppLogger(
      sink: (_, m) => out.add(m),
      scrubber: scrubber,
      diagnostics: log,
      minLevel: LogLevel.debug,
    ).info('GET https://nas.canary.example/api failed, ${_keyed()}');
    expect(scrubber.calls, 1);
    expect(out.single, isNot(contains('canary.example')));
    expect(log.entries.single.message, out.single);
  });

  test('a line captured below the sink level is scrubbed once too', () {
    final scrubber = _Counting();
    final log = DiagnosticsLog(scrubber: scrubber)
      ..enabled = true
      ..level = LogLevel.debug;
    final out = <String>[];
    AppLogger(
      sink: (_, m) => out.add(m),
      scrubber: scrubber,
      diagnostics: log,
    ).debug('host nas.canary.example');
    expect(scrubber.calls, 1);
    expect(out, isEmpty);
    expect(log.entries.single.message, isNot(contains('canary.example')));
  });

  test('DiagnosticsLog.add still scrubs a line from any other caller', () {
    final log = DiagnosticsLog()
      ..enabled = true
      ..level = LogLevel.debug
      ..add(LogLevel.info, 'host nas.canary.example');
    expect(log.entries.single.message, isNot(contains('canary.example')));
  });
}
