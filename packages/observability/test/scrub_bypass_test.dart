// SPDX-License-Identifier: GPL-3.0-or-later

// Only AppLogger may write an already-scrubbed line into the diagnostics log.
// Any other caller must go through DiagnosticsLog.add, which scrubs. The
// compiler enforces it (the writer is library-private); these tests ask the
// analyzer, so the rule cannot be loosened quietly.

import 'dart:io';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

void main() {
  group('scrubbing cannot be skipped from outside the library', () {
    // One analyzer run for every probe (each run costs seconds).
    const probes = {
      'control': "log.add(LogLevel.info, 'x');",
      'public': "log.addScrubbed(LogLevel.info, 'x');",
      'private': "log._addScrubbed(LogLevel.info, 'x');",
      'store': "log._store(LogLevel.info, 'x');",
    };
    late Directory dir;
    late Map<String, List<String>> errors;

    setUpAll(() async {
      // test/.generated/ is git-ignored (see .gitignore).
      dir = Directory('test/.generated/bypass').absolute
        ..createSync(recursive: true);
      for (final e in probes.entries) {
        File('${dir.path}/${e.key}.dart').writeAsStringSync(
          "import 'package:observability/observability.dart';\n"
          'void main() {\n  final log = DiagnosticsLog();\n  ${e.value}\n}\n',
        );
      }
      final result = await Process.run('dart', [
        'analyze',
        '--format=machine',
        dir.path,
      ]);
      errors = {for (final k in probes.keys) k: []};
      for (final line in '${result.stdout}'.split('\n')) {
        if (!line.startsWith('ERROR|')) continue;
        for (final k in probes.keys) {
          if (line.contains('/$k.dart|')) errors[k]!.add(line);
        }
      }
    });
    tearDownAll(() => dir.parent.deleteSync(recursive: true));

    test('the control (add) compiles, so the probes themselves work', () {
      expect(errors['control'], isEmpty);
    });

    test('a public addScrubbed would let a caller skip the scrubber', () {
      expect(errors['public'], isNotEmpty);
      expect(errors['public']!.join(), contains('UNDEFINED_METHOD'));
    });

    test('nor can the private writers be reached by name', () {
      expect(errors['private'], isNotEmpty);
      expect(errors['store'], isNotEmpty);
    });

    test('the library still exports the logger that uses it', () {
      final log = DiagnosticsLog()..enabled = true;
      AppLogger(sink: (_, _) {}, diagnostics: log).info('hello');
      expect(log.entries.single.message, 'hello');
    });
  });

  test('no source outside the library mentions the writer', () {
    final hits = <String>[];
    for (final root in ['../../apps', '../../packages']) {
      for (final f in Directory(root).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('.dart_tool') || f.path.contains('/build/')) {
          continue;
        }
        if (f.path.endsWith('observability/test/scrub_bypass_test.dart')) {
          continue;
        }
        if (f.readAsStringSync().contains('ddScrubbed')) hits.add(f.path);
      }
    }
    // Directory listing order is filesystem-dependent; compare sorted.
    hits.sort();
    expect(hits, [
      endsWith('observability/lib/src/diagnostics.dart'),
      endsWith('observability/lib/src/logger.dart'),
    ]);
  });
}
