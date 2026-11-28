// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

import 'canary_corpus.dart';

const _info = DiagnosticsInfo(
  appVersion: '0.1.0+1',
  buildMode: 'release',
  platform: 'Android API 34',
  locale: 'en',
);

void _clean(String sink, String text, {Iterable<Canary>? cases}) {
  for (final c in cases ?? canaryCorpus) {
    for (final f in c.forbidden) {
      expect(
        text.toLowerCase(),
        isNot(contains(f.toLowerCase())),
        reason: '[$sink] ${c.name}: "$f" leaked',
      );
    }
  }
}

void main() {
  group('every sink is clean for the corpus', () {
    test('the diagnostics log (the view)', () {
      final log = DiagnosticsLog(capacity: 100)
        ..enabled = true
        ..level = LogLevel.debug;
      for (final c in canaryCorpus) {
        log.add(LogLevel.error, c.text);
      }
      final shown = log.view.map((e) => e.message).join('\n');
      expect(log.length, canaryCorpus.length);
      _clean('log view', shown);
    });

    test('AppLogger sink and its diagnostics capture', () {
      final out = <String>[];
      final log = DiagnosticsLog()
        ..enabled = true
        ..level = LogLevel.debug;
      final logger = AppLogger(
        sink: (_, m) => out.add(m),
        minLevel: LogLevel.debug,
        diagnostics: log,
      );
      for (final c in canaryCorpus) {
        logger
          ..info(c.text)
          ..error('failed', error: c.text);
      }
      _clean('AppLogger sink', out.join('\n'));
      _clean('AppLogger capture', log.view.map((e) => e.message).join('\n'));
    });

    test('bundle text, summary and bytes', () {
      final bundle = DiagnosticsBundle.build(
        info: _info,
        errorCategories: [for (final c in canaryCorpus) c.text],
        entries: [
          for (final c in canaryCorpus)
            LogEntry(
              time: DateTime.utc(2026),
              level: LogLevel.error,
              message: c.text,
            ),
        ],
      );
      _clean('bundle.text', bundle.text);
      _clean('bundle.summaryText', bundle.summaryText);
      _clean('bundle.bytes', utf8.decode(bundle.bytes));
    });

    test('the GitHub issue address: raw, decoded and double decoded', () {
      final bundle = DiagnosticsBundle.build(
        info: _info,
        errorCategories: [for (final c in canaryCorpus) c.text],
        entries: const [],
      );
      final url = GithubIssueLink.build(
        repository: Uri.parse('https://github.com/example/consolarr'),
        title: 'Diagnostics',
        body: bundle.summaryText,
      ).toString();
      _clean('issue url raw', url);
      final once = Uri.decodeFull(url);
      _clean('issue url decoded', once);
      _clean('issue url double decoded', Uri.decodeFull(once));
    });

    test('breadcrumbs cannot carry free text at all', () {
      final crumbs = Breadcrumbs();
      for (final s in ScreenName.values) {
        crumbs.add(Breadcrumb.navigation(s));
      }
      for (final e in ErrorCategoryParam.values) {
        crumbs.add(Breadcrumb.apiError(e, ServiceKindParam.sonarr));
      }
      _clean('breadcrumbs', crumbs.entries.map((c) => c.line).join('\n'));
    });
  });

  group('redaction behaviour', () {
    const scrubber = DiagnosticsScrubber();

    test('scrub is idempotent over the corpus', () {
      for (final c in canaryCorpus) {
        final once = scrubber.scrub(c.text);
        expect(scrubber.scrub(once), once, reason: c.name);
      }
    });

    test('redactText is idempotent over the corpus', () {
      const r = Redactor();
      for (final c in canaryCorpus) {
        final once = r.redactText(c.text);
        expect(r.redactText(once), once, reason: c.name);
      }
    });

    test('never throws on arbitrary input (seeded fuzz)', () {
      final rng = Random(20260101);
      const alphabet =
          'abcXYZ019 :/\\.@?&=%[]{}()"\'<>|;,-_+~#\n\t\r'
          'مسلسل😀\u{1F600}ß\u0000\uFFFF';
      final runes = alphabet.runes.toList();
      const fragments = [
        'http://',
        'https://u:p@',
        'magnet:?xt=',
        'apikey=',
        'Authorization: ',
        'Cookie: ',
        '2001:db8::',
        '192.0.2.',
        r'C:\',
        '/mnt/',
        '%2F',
        '%zz',
        '[',
      ];
      for (var i = 0; i < 400; i++) {
        final b = StringBuffer();
        final n = rng.nextInt(300);
        for (var j = 0; j < n; j++) {
          if (rng.nextInt(6) == 0) {
            b.write(fragments[rng.nextInt(fragments.length)]);
          } else {
            b.writeCharCode(runes[rng.nextInt(runes.length)]);
          }
        }
        final s = b.toString();
        expect(() => const Redactor().redactText(s), returnsNormally);
        expect(() => scrubber.scrub(s), returnsNormally);
        final once = scrubber.scrub(s);
        expect(scrubber.scrub(once), once, reason: 'idempotent for #$i');
      }
    });
  });
}
