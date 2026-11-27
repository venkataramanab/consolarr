// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorCategory', () {
    test('has the documented categories with stable codes', () {
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
        'tls_untrusted',
        'tls_expired',
        'redirect_refused',
        'response_too_large',
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

  group('ServerProfile.parse address hardening', () {
    String? detail(String a) => ServerProfile.parse(
      id: 'p',
      name: 'n',
      kind: ServiceKind.sonarr,
      address: a,
    ).errorOrNull?.debugDetail;

    test('rejects ports outside 1..65535', () {
      for (final a in [
        'https://nas.example:99999',
        'https://nas.example:65536',
        'https://nas.example:0',
        'https://nas.example:-1',
      ]) {
        expect(detail(a), 'invalid port', reason: a);
      }
    });

    test('accepts the port range limits', () {
      for (final a in ['https://nas.example:1', 'https://nas.example:65535']) {
        expect(detail(a), isNull, reason: a);
      }
    });

    test('rejects a backslash anywhere in the address', () {
      expect(detail(r'https://evil.example\@nas.example'), 'invalid address');
      expect(detail(r'https://nas.example\sonarr'), 'invalid address');
    });

    test('rejects non-ASCII hosts with a dedicated reason', () {
      expect(detail('https://münchen.example'), 'host must be ascii');
      expect(
        ServerProfile.parse(
          id: 'p',
          name: 'n',
          kind: ServiceKind.sonarr,
          address: 'https://nas.example',
          alternateAddress: 'https://münchen.example:99999',
        ).errorOrNull?.debugDetail,
        isNotNull,
      );
    });

    test('a valid alternate address is preserved', () {
      final p = ServerProfile.parse(
        id: 'p',
        name: 'n',
        kind: ServiceKind.sonarr,
        address: 'https://nas.example',
        alternateAddress: 'https://alt.example:8443',
      ).valueOrNull!;
      expect(p.alternateAddress.toString(), 'https://alt.example:8443');
    });
  });

  group('parseRowsTolerant', () {
    int parse(Object? v) => v is int ? v : throw const FormatException('x');

    test('skips malformed rows and counts them', () {
      final r = parseRowsTolerant([1, 'x', 3, null], parse);
      expect(r.items, [1, 3]);
      expect(r.skipped, 2);
    });

    test('an empty list is fine; all-malformed is a format error', () {
      expect(parseRowsTolerant(<Object?>[], parse).items, isEmpty);
      expect(() => parseRowsTolerant(['a', 'b'], parse), throwsFormatException);
    });
  });

  test('kOfflineFallbackCategories never hides auth, version or TLS', () {
    for (final c in [
      ErrorCategory.authFailed,
      ErrorCategory.unsupportedVersion,
      ErrorCategory.tlsPinMismatch,
      ErrorCategory.tlsUntrusted,
      ErrorCategory.tlsExpired,
      ErrorCategory.cleartextRefused,
      ErrorCategory.redirectRefused,
    ]) {
      expect(kOfflineFallbackCategories, isNot(contains(c)));
    }
    expect(kOfflineFallbackCategories, contains(ErrorCategory.timeout));
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

  group('ServerProfile extended fields', () {
    ServerProfile? build({
      String address = 'https://sonarr.example',
      String pathPrefix = '',
      AuthMode authMode = AuthMode.apiKey,
      List<String> headerNames = const [],
      String? alternateAddress,
    }) => ServerProfile.parse(
      id: 'p1',
      name: 'Test',
      kind: ServiceKind.sonarr,
      address: address,
      pathPrefix: pathPrefix,
      authMode: authMode,
      headerNames: headerNames,
      alternateAddress: alternateAddress,
    ).valueOrNull;

    test('defaults: no prefix, api key, no headers, no alternate', () {
      final p = build()!;
      expect(p.pathPrefix, '');
      expect(p.authMode, AuthMode.apiKey);
      expect(p.headerNames, isEmpty);
      expect(p.alternateAddress, isNull);
      expect(p.baseUri.toString(), 'https://sonarr.example');
    });

    test('normalises the path prefix and builds baseUri', () {
      expect(build(pathPrefix: 'sonarr/')!.pathPrefix, '/sonarr');
      expect(build(pathPrefix: '/a/b//')!.pathPrefix, '/a/b');
      expect(
        build(pathPrefix: '/sonarr')!.baseUri.toString(),
        'https://sonarr.example/sonarr',
      );
    });

    test('a path inside the address is folded into the prefix', () {
      final p = build(address: 'https://nas.example/tv/')!;
      expect(p.pathPrefix, '/tv');
      expect(p.address.path, isEmpty);
      expect(p.baseUri.toString(), 'https://nas.example/tv');
    });

    test('rejects traversal, queries and whitespace in the prefix', () {
      for (final bad in ['/../x', '/a?key=1', '/a#b', '/a b', r'/a\b']) {
        expect(build(pathPrefix: bad), isNull, reason: bad);
      }
    });

    test('validates header names (tokens only, bounded, no duplicates)', () {
      expect(build(headerNames: ['X-Gateway-Token'])!.headerNames, [
        'X-Gateway-Token',
      ]);
      expect(build(headerNames: ['bad name']), isNull);
      expect(build(headerNames: ['A', 'a']), isNull);
      expect(build(headerNames: List.generate(21, (i) => 'H$i')), isNull);
    });

    test('alternate address obeys the same address rules', () {
      final p = build(alternateAddress: 'http://192.0.2.10:8989')!;
      expect(p.alternateAddress!.host, '192.0.2.10');
      expect(build(alternateAddress: 'https://u:p@x.example'), isNull);
      expect(build(alternateAddress: 'https://x.example/?k=1'), isNull);
    });

    test('toString still omits the address', () {
      expect(
        '${build(pathPrefix: '/secret-prefix')}',
        isNot(contains('prefix')),
      );
    });
  });
}
