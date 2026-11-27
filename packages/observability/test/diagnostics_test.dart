// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:observability/observability.dart';
import 'package:test/test.dart';

/// Fake secrets, hosts, titles and magnet links that must never leave the app
/// in a diagnostics bundle (RFC 5737 addresses and `.example` names only).
const _canaries = [
  'hunter2-canary',
  'nas.private.example',
  '192.0.2.77',
  '2001:db8::77',
  'alice-the-admin',
  'Fake Show Title S01E01',
  'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Fake+Movie',
  '/storage/emulated/0/Download/Fake Movie 2020.mkv',
  r'C:\Users\alice\Videos\fake.mkv',
  'abcd1234canarytoken',
  'canary-cookie-value',
  'fake.user@mail.example',
];

const _info = DiagnosticsInfo(
  appVersion: '0.1.0+1',
  buildMode: 'release',
  platform: 'Android API 34',
  locale: 'en',
);

List<String> _dirtyLines() => [
  'GET https://alice-the-admin:hunter2-canary@nas.private.example:8989/api/v3/series?apikey=abcd1234canarytoken failed',
  'connect to 192.0.2.77:8080 and [2001:db8::77]:80 refused',
  'loading "Fake Show Title S01E01" failed',
  'title=Fake Show Title S01E01 user=alice-the-admin',
  'added magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Fake+Movie',
  'file /storage/emulated/0/Download/Fake Movie 2020.mkv missing',
  r'file C:\Users\alice\Videos\fake.mkv missing',
  'Cookie: SID=canary-cookie-value',
  'X-Custom-Auth-Thing: abcd1234canarytoken',
  'contact fake.user@mail.example',
];

void main() {
  group('DiagnosticsScrubber', () {
    const scrubber = DiagnosticsScrubber(
      knownValues: [
        'alice-the-admin',
        'Fake Show Title S01E01',
        'hunter2-canary',
      ],
    );

    test('removes every canary from dirty lines', () {
      final out = _dirtyLines().map(scrubber.scrub).join('\n');
      for (final c in _canaries) {
        expect(out, isNot(contains(c)), reason: c);
      }
    });

    test('keeps ordinary diagnostic text and times', () {
      expect(
        scrubber.scrub('12:30:45 refresh finished with 3 errors (timeout)'),
        '12:30:45 refresh finished with 3 errors (timeout)',
      );
    });

    test('is idempotent', () {
      for (final l in _dirtyLines()) {
        final once = scrubber.scrub(l);
        expect(scrubber.scrub(once), once);
      }
    });

    test('removes single-label host:port and mixed-case host names', () {
      const cases = {
        'connect to nas:8989 refused': 'nas:8989',
        'connect to NAS-Box:8989 refused': 'NAS-Box:8989',
        'host Seedbox01:443 timed out': 'Seedbox01:443',
        'resolve Media.Home.Example failed': 'Media.Home.Example',
        'resolve NAS.EXAMPLE.COM failed': 'NAS.EXAMPLE.COM',
      };
      for (final e in cases.entries) {
        final out = scrubber.scrub(e.key);
        expect(out, isNot(contains(e.value)), reason: e.key);
        expect(scrubber.scrub(out), out, reason: 'idempotent: ${e.key}');
      }
    });

    test('removes bare hex and base32 runs of 16+ characters', () {
      const passkeys = [
        '0123456789abcdef',
        'DEADBEEFcafe0123',
        '0123456789abcdef0123456789',
        'JBSWY3DPEHPK3PXP',
        'jbswy3dpehpk3pxp',
        'MFRGGZDFMZTWQ2LKNNWG23TP',
      ];
      for (final p in passkeys) {
        expect(scrubber.scrub('announce passkey $p ok'), isNot(contains(p)));
      }
    });

    test('keeps short ids, times and long plain words', () {
      for (final t in [
        'retry 3 of 5 at 12:30:45',
        'build 0123abcd',
        'internationalization failed',
      ]) {
        expect(scrubber.scrub(t), t);
      }
    });

    test('known values are removed case-insensitively', () {
      expect(
        scrubber.scrub('user ALICE-THE-ADMIN logged'),
        isNot(contains('ALICE')),
      );
    });
  });

  group('DiagnosticsLog', () {
    test('is off by default and records nothing while off', () {
      final log = DiagnosticsLog();
      log.add(LogLevel.error, 'boom');
      expect(log.enabled, isFalse);
      expect(log.entries, isEmpty);
    });

    test('redacts at write time', () {
      final log = DiagnosticsLog()..enabled = true;
      log.add(LogLevel.error, 'Authorization: Bearer abcdefghijkl');
      expect(log.entries.single.message, isNot(contains('abcdefghijkl')));
    });

    test('ring buffer keeps the newest entries up to the cap', () {
      final log = DiagnosticsLog(capacity: 3)..enabled = true;
      for (var i = 0; i < 5; i++) {
        log.add(LogLevel.info, 'line $i');
      }
      expect(log.entries.map((e) => e.message), ['line 2', 'line 3', 'line 4']);
    });

    test('circular buffer: lazy view, length, entryAt and version', () {
      final log = DiagnosticsLog(capacity: 3)..enabled = true;
      final v0 = log.version;
      for (var i = 0; i < 7; i++) {
        log.add(LogLevel.info, 'line $i');
      }
      expect(log.version, greaterThan(v0));
      expect(log.length, 3);
      expect(log.entryAt(0).message, 'line 4');
      expect(log.entryAt(2).message, 'line 6');
      expect(log.view.map((e) => e.message), ['line 4', 'line 5', 'line 6']);
      expect(log.view.length, 3);
      expect(() => log.entryAt(3), throwsRangeError);
      // `entries` is an explicit copy: later lines do not change it.
      final copy = log.entries;
      log.add(LogLevel.info, 'line 7');
      expect(copy.map((e) => e.message), ['line 4', 'line 5', 'line 6']);
      expect(log.entryAt(0).message, 'line 5');
    });

    test('add bumps the version once; clearing an empty log does not', () {
      final log = DiagnosticsLog(capacity: 1000)..enabled = true;
      final before = log.version;
      log.add(LogLevel.info, 'a');
      expect(log.version, before + 1);
      log.clear();
      expect(log.version, before + 2);
      log.clear();
      expect(log.version, before + 2);
      expect(log.length, 0);
    });

    test('an entry is capped at about 1 KB with a marker', () {
      final log = DiagnosticsLog()..enabled = true;
      log.add(LogLevel.info, 'x ' * 4000);
      final m = log.entryAt(0).message;
      expect(m.length, lessThanOrEqualTo(DiagnosticsLog.maxMessageLength));
      expect(m, endsWith(DiagnosticsLog.truncationMarker));
      log.add(LogLevel.info, 'short');
      expect(log.entryAt(1).message, 'short');
    });

    test('level selector drops lower levels', () {
      final log = DiagnosticsLog()
        ..enabled = true
        ..level = LogLevel.warning;
      log.add(LogLevel.info, 'quiet');
      log.add(LogLevel.error, 'loud');
      expect(log.entries.map((e) => e.message), ['loud']);
    });

    test('clear empties; turning off also clears', () {
      final log = DiagnosticsLog()..enabled = true;
      log.add(LogLevel.error, 'x');
      log.clear();
      expect(log.entries, isEmpty);
      log.add(LogLevel.error, 'y');
      log.enabled = false;
      expect(log.entries, isEmpty);
    });

    test('notifies listeners on change', () {
      final log = DiagnosticsLog()..enabled = true;
      var n = 0;
      log.addListener(() => n++);
      log.add(LogLevel.error, 'x');
      log.clear();
      expect(n, 2);
    });

    test(
      'AppLogger feeds it; the log level is independent of the sink level',
      () {
        final log = DiagnosticsLog()
          ..enabled = true
          ..level = LogLevel.debug;
        final sunk = <String>[];
        final logger = AppLogger(sink: (l, m) => sunk.add(m), diagnostics: log);
        logger.debug('detail');
        logger.error('failed', error: 'password=hunter2-canary');
        expect(sunk, hasLength(1));
        expect(log.entries, hasLength(2));
        expect(
          log.entries.map((e) => e.message).join(),
          isNot(contains('hunter2')),
        );
      },
    );
  });

  group('DiagnosticsBundle', () {
    test('canary scrub: nothing leaks into the preview text', () {
      final log = DiagnosticsLog()..enabled = true;
      for (final l in _dirtyLines()) {
        log.add(LogLevel.error, l);
      }
      final bundle = DiagnosticsBundle.build(
        info: _info,
        errorCategories: const ['timeout', 'auth_failed'],
        entries: log.entries,
        scrubber: const DiagnosticsScrubber(
          knownValues: ['alice-the-admin', 'Fake Show Title S01E01'],
        ),
      );
      for (final c in _canaries) {
        expect(bundle.text, isNot(contains(c)), reason: c);
      }
    });

    test('scrubs again at build time even for lines that bypassed the log', () {
      final bundle = DiagnosticsBundle.build(
        info: _info,
        errorCategories: const [],
        entries: [
          LogEntry(
            time: DateTime.utc(2026),
            level: LogLevel.error,
            message: 'raw 192.0.2.77 hunter2-canary',
          ),
        ],
        scrubber: const DiagnosticsScrubber(knownValues: ['hunter2-canary']),
      );
      expect(bundle.text, isNot(contains('192.0.2.77')));
      expect(bundle.text, isNot(contains('hunter2-canary')));
    });

    test('contains exactly the documented sections, all in the text', () {
      final bundle = DiagnosticsBundle.build(
        info: _info,
        errorCategories: const ['timeout'],
        entries: const [],
      );
      expect(bundle.sections.map((s) => s.id), [
        'app',
        'platform',
        'locale',
        'error_categories',
        'log',
      ]);
      for (final s in bundle.sections) {
        expect(bundle.text, contains(s.body));
      }
      expect(bundle.text, contains('0.1.0+1'));
      expect(bundle.text, contains('Android API 34'));
      expect(bundle.text, contains('timeout'));
    });

    test('shared bytes equal the previewed text (utf-8)', () {
      final bundle = DiagnosticsBundle.build(
        info: _info,
        errorCategories: const ['timeout'],
        entries: const [],
      );
      expect(utf8Decode(bundle.bytes), bundle.text);
    });
  });

  group('summary', () {
    test('summaryText has every section but the log', () {
      final bundle = DiagnosticsBundle.build(
        info: const DiagnosticsInfo(
          appVersion: '1.0.0+1',
          buildMode: 'release',
          platform: 'Android API 34',
          locale: 'en',
        ),
        errorCategories: const ['timeout'],
        entries: [
          LogEntry(
            time: DateTime.utc(2026),
            level: LogLevel.info,
            message: 'secret log line',
          ),
        ],
      );
      expect(bundle.logIsEmpty, isFalse);
      expect(bundle.summaryText, contains('Android API 34'));
      expect(bundle.summaryText, contains('timeout'));
      expect(bundle.summaryText, isNot(contains('secret log line')));
      expect(bundle.summaryText, isNot(contains('## Log')));
      expect(bundle.text, contains('secret log line'));
    });
  });

  group('GithubIssueLink', () {
    final repo = Uri.parse('https://github.com/example-owner/example-repo');

    test('https only, issues/new, title and body in the query', () {
      final uri = GithubIssueLink.build(
        repository: repo,
        title: 'Diagnostics',
        body: 'hello',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, '/example-owner/example-repo/issues/new');
      expect(uri.queryParameters['title'], 'Diagnostics');
      expect(uri.queryParameters['body'], 'hello');
    });

    test('long bodies are truncated to the length bound with a note', () {
      final uri = GithubIssueLink.build(
        repository: repo,
        title: 'T',
        body: List.filled(5000, 'line with spaces & symbols é').join('\n'),
        truncationNote: 'ATTACH THE FILE',
      );
      expect(
        uri.toString().length,
        lessThanOrEqualTo(GithubIssueLink.maxUrlLength),
      );
      expect(uri.queryParameters['body'], contains('ATTACH THE FILE'));
    });

    test('only exactly https://github.com is accepted', () {
      for (final bad in [
        'https://github.com.evil.example/a/b',
        'https://evil-github.com/a/b',
        'https://GITHUB.com.example/a/b',
        'https://example.com/a/b',
        'https://user@github.example/a/b',
        'ftp://github.com/a/b',
      ]) {
        expect(
          () => GithubIssueLink.build(
            repository: Uri.parse(bad),
            title: 't',
            body: 'b',
          ),
          throwsArgumentError,
          reason: bad,
        );
      }
      final ok = GithubIssueLink.build(
        repository: Uri.parse('https://github.com/a/b'),
        title: 't',
        body: 'b',
      );
      expect(ok.scheme, 'https');
      expect(ok.host, 'github.com');
    });

    test('refuses a non-https repository', () {
      expect(
        () => GithubIssueLink.build(
          repository: Uri.parse('http://github.com/a/b'),
          title: 't',
          body: 'b',
        ),
        throwsArgumentError,
      );
    });
  });
}

String utf8Decode(List<int> bytes) => const Utf8Decoder().convert(bytes);
