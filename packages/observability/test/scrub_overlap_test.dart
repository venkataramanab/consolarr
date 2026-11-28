// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

import 'canary_corpus.dart';

void main() {
  const mark = Redactor.placeholder;

  group('known values that overlap the placeholder', () {
    // Each is a case-insensitive substring of `[REDACTED]`.
    const overlapping = ['ted', 'red', 'act', 'eda', 'REDACTED', 'DACT'];

    for (final v in overlapping) {
      test('"$v" never corrupts an existing placeholder', () {
        final scrubber = DiagnosticsScrubber(knownValues: [v]);
        const line = 'apikey=0123456789abcdef0123456789abcdef then more';
        final out = scrubber.scrub(line);
        expect(out, isNot(contains('[REDAC[')), reason: out);
        expect(out, contains(mark));
        expect(scrubber.scrub(out), out, reason: 'idempotent');
        // The placeholder is never split or nested.
        expect(RegExp(r'\[REDACTED\]').allMatches(out), isNotEmpty);
        expect(out.replaceAll(mark, ''), isNot(contains('REDACTED')));
        expect(out.replaceAll(mark, ''), isNot(contains('[')));
      });

      test('"$v" is still removed from the text between placeholders', () {
        final scrubber = DiagnosticsScrubber(knownValues: [v]);
        final out = scrubber.scrub(
          'a apikey=0123456789abcdef0123456789abcdef b ${v.toUpperCase()} '
          'and ${v.toLowerCase()} c',
        );
        final rest = out.replaceAll(mark, '');
        expect(rest.toLowerCase(), isNot(contains(v.toLowerCase())));
        expect(scrubber.scrub(out), out, reason: 'idempotent');
      });

      test('"$v" does not bloat the output', () {
        final scrubber = DiagnosticsScrubber(knownValues: [v]);
        final line = List.filled(20, 'password=hunter2xyz').join('\n');
        expect(
          scrubber.scrub(line).length,
          lessThanOrEqualTo(const DiagnosticsScrubber().scrub(line).length),
        );
      });

      test('"$v": corpus stays clean and idempotent', () {
        final scrubber = DiagnosticsScrubber(knownValues: [v]);
        for (final c in canaryCorpus) {
          final once = scrubber.scrub(c.text);
          expect(scrubber.scrub(once), once, reason: c.name);
          for (final f in c.forbidden) {
            expect(once, isNot(contains(f)), reason: '${c.name} leaked $f');
          }
          expect(once, isNot(contains('[REDAC[')), reason: c.name);
        }
      });
    }

    test('seeded fuzz stays idempotent with overlapping known values', () {
      final scrubber = const DiagnosticsScrubber(
        knownValues: ['ted', 'red', 'act', 'eda', 'REDACTED'],
      );
      final rng = Random(20260102);
      const pieces = [
        '[REDACTED]',
        'red',
        'ted',
        'ACT',
        'apikey=abc12345678',
        ' ',
        'x',
        '[',
        ']',
        'REDACTED',
        '"a b"',
      ];
      for (var i = 0; i < 400; i++) {
        final s = [
          for (var j = rng.nextInt(12); j > 0; j--)
            pieces[rng.nextInt(pieces.length)],
        ].join();
        final once = scrubber.scrub(s);
        expect(scrubber.scrub(once), once, reason: 'idempotent for "$s"');
      }
    });
  });

  group('UNC paths', () {
    const scrubber = DiagnosticsScrubber();
    const cases = {
      'unc with extension and spaces': (
        r'missing \\nascanary\media share\My Canary Shows\Pilot Ep.mkv now',
        ['nascanary', 'media share', 'My Canary Shows', 'Pilot Ep'],
      ),
      'unc root folder, no extension': (
        r'rootfolder \\canaryhost\tvshows\Canary Library Name',
        ['canaryhost', 'tvshows', 'Canary Library'],
      ),
      'unc, host and share only': (
        r'cannot open \\canaryhost\canaryshare',
        ['canaryhost', 'canaryshare'],
      ),
      'unc, long-path prefix': (
        r'open \\?\UNC\canaryhost\share\Canary Dir\f.mkv',
        ['canaryhost', 'Canary Dir'],
      ),
      'unc, quoted': (
        r'dir "\\canaryhost\share\Canary Movie (2020)" gone',
        ['canaryhost', 'Canary Movie'],
      ),
      'forward-slash unc': (
        'open //canaryhost/share/Canary Dir/ep 1.mkv',
        ['canaryhost', 'Canary Dir'],
      ),
    };
    cases.forEach((name, spec) {
      test(name, () {
        final out = scrubber.scrub(spec.$1);
        for (final f in spec.$2) {
          expect(out, isNot(contains(f)), reason: out);
        }
        expect(scrubber.scrub(out), out, reason: 'idempotent');
      });
    });

    test('the text after a quoted UNC path survives', () {
      expect(
        scrubber.scrub(r'dir "\\canaryhost\share\Canary Movie" gone'),
        contains('gone'),
      );
    });
  });
}
