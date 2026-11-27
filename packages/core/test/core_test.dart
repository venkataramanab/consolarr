// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorCategory', () {
    test('has the nine documented categories with stable codes', () {
      expect(ErrorCategory.values.map((c) => c.code), [
        'auth_failed',
        'timeout',
        'tls_pin_mismatch',
        'cleartext_refused',
        'unsupported_version',
        'not_found',
        'server_error',
        'network_unreachable',
        'parse_error',
      ]);
    });

    test('fromCode round-trips and rejects unknown codes', () {
      for (final c in ErrorCategory.values) {
        expect(ErrorCategory.fromCode(c.code), c);
      }
      expect(ErrorCategory.fromCode('nope'), isNull);
    });
  });

  group('Result', () {
    test('ok / err accessors', () {
      const ok = Result<int>.ok(1);
      const err = Result<int>.err(AppError(ErrorCategory.timeout));
      expect(ok.isOk, isTrue);
      expect(ok.valueOrNull, 1);
      expect(ok.errorOrNull, isNull);
      expect(err.isErr, isTrue);
      expect(err.valueOrNull, isNull);
      expect(err.errorOrNull?.category, ErrorCategory.timeout);
    });

    test('map transforms ok and passes err through', () {
      expect(const Result<int>.ok(2).map((v) => v * 2), const Ok<int>(4));
      const err = Result<int>.err(AppError(ErrorCategory.notFound));
      expect(
        err.map((v) => v * 2).errorOrNull?.category,
        ErrorCategory.notFound,
      );
    });

    test('when folds both cases', () {
      expect(
        const Result<int>.ok(3)
            .when(ok: (v) => 'v$v', err: (e) => e.toString()),
        'v3',
      );
      expect(
        const Result<int>.err(AppError(ErrorCategory.authFailed))
            .when(ok: (v) => 'v$v', err: (e) => e.category.code),
        'auth_failed',
      );
    });
  });

  group('ServerProfile.parse', () {
    ServerProfile build(String address, {bool allowCleartext = false}) =>
        ServerProfile.parse(
          id: 'p1',
          name: 'Test',
          kind: ServiceKind.sonarr,
          address: address,
          allowCleartext: allowCleartext,
        ).valueOrNull!;

    test('accepts https and http addresses on reserved example hosts', () {
      expect(build('https://sonarr.example/').isSecure, isTrue);
      expect(build('http://192.0.2.10:8989').isSecure, isFalse);
    });

    test('rejects credentials in the URL', () {
      final r = ServerProfile.parse(
        id: 'p1',
        name: 'Test',
        kind: ServiceKind.radarr,
        address: 'https://user:test-key-0000@radarr.example/',
      );
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
    });

    test('rejects query strings (secrets travel in query strings)', () {
      for (final bad in [
        'https://sonarr.example/?apikey=test-key-0000',
        'https://sonarr.example/api?x=1',
        'https://sonarr.example/?',
        'http://192.0.2.10:8989/?token=t',
      ]) {
        final r = ServerProfile.parse(
          id: 'p1',
          name: 'Test',
          kind: ServiceKind.sonarr,
          address: bad,
        );
        expect(r.errorOrNull?.category, ErrorCategory.parseError, reason: bad);
        expect(r.errorOrNull?.debugDetail, isNot(contains('test-key')));
      }
      // A path without a query is fine.
      expect(build('https://sonarr.example/sonarr').isSecure, isTrue);
    });

    test('rejects non-http schemes and garbage', () {
      for (final bad in ['ftp://host.example', 'not a url', '', '//host']) {
        final r = ServerProfile.parse(
          id: 'p',
          name: 'n',
          kind: ServiceKind.deluge,
          address: bad,
        );
        expect(r.errorOrNull?.category, ErrorCategory.parseError, reason: bad);
      }
    });

    test('toString does not leak the address', () {
      expect(
        build('https://secret-host.example/').toString(),
        isNot(contains('secret-host')),
      );
    });
  });

  group('CleartextPolicy', () {
    ServerProfile profile(String address, {bool allow = false}) =>
        ServerProfile.parse(
          id: 'p',
          name: 'n',
          kind: ServiceKind.qbittorrent,
          address: address,
          allowCleartext: allow,
        ).valueOrNull!;

    test('https is always allowed', () {
      expect(CleartextPolicy.check(profile('https://a.example')).isOk, isTrue);
    });

    test('http is refused unless the server opted in', () {
      expect(
        CleartextPolicy.check(profile('http://a.example'))
            .errorOrNull
            ?.category,
        ErrorCategory.cleartextRefused,
      );
      expect(
        CleartextPolicy.check(profile('http://a.example', allow: true)).isOk,
        isTrue,
      );
    });

    test('redirects: same host+scheme only, never downgrade', () {
      final https = Uri.parse('https://a.example/x');
      expect(
        CleartextPolicy.isRedirectAllowed(
          https,
          Uri.parse('https://a.example/y'),
        ),
        isTrue,
      );
      expect(
        CleartextPolicy.isRedirectAllowed(
          https,
          Uri.parse('http://a.example/y'),
        ),
        isFalse,
      );
      expect(
        CleartextPolicy.isRedirectAllowed(
          https,
          Uri.parse('https://b.example/y'),
        ),
        isFalse,
      );
    });
  });
}
