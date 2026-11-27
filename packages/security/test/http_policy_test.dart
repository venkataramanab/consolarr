// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';

import 'support/certs.dart';
import 'support/test_server.dart';

Future<AppError> _failure(Future<Object?> call) async {
  try {
    await call;
  } on DioException catch (e) {
    return appErrorFromDio(e);
  }
  fail('expected a failure');
}

void main() {
  late CertFactory certs;
  final servers = <TestServer>[];

  setUpAll(() => certs = CertFactory.create());
  tearDownAll(() => certs.dispose());
  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
  });

  Future<TestServer> serve({TestCert? cert, Handler? handler}) async {
    final s = await TestServer.start(cert: cert, handler: handler);
    servers.add(s);
    return s;
  }

  DefaultSecureHttpClientFactory factory({
    HttpLimits limits = const HttpLimits(),
    PinStore? pins,
  }) => DefaultSecureHttpClientFactory(
    pins: pins ?? InMemoryPinStore(),
    limits: limits,
  );

  Future<(TestServer, ServerProfile, Dio)> tlsServer({
    Handler? handler,
    HttpLimits limits = const HttpLimits(),
    List<TestServer>? alsoPin,
  }) async {
    final cert = certs.selfSigned();
    final s = await serve(cert: cert, handler: handler);
    final pins = InMemoryPinStore();
    final profile = s.profile();
    final key = PinKey.forProfile(profile);
    final fp = CertificateFingerprint.parse(cert.sha256Hex);
    await pins.write(
      key,
      fp,
      UserPinConfirmation.userAccepted(key: key, fingerprint: fp),
    );
    return (s, profile, factory(limits: limits, pins: pins).create(profile));
  }

  group('cleartext policy (SRV-07)', () {
    test('http is refused without the opt-in, nothing is sent', () async {
      final s = await serve();
      final dio = factory().create(s.profile());
      final err = await _failure(dio.get<Object>('/api'));
      expect(err.category, ErrorCategory.cleartextRefused);
      expect(s.seen, isEmpty);
    });

    test('http works with the per-server opt-in', () async {
      final s = await serve();
      final dio = factory().create(s.profile(allowCleartext: true));
      expect((await dio.get<Object>('/api')).statusCode, 200);
    });

    test('baseUri includes the path prefix', () async {
      final s = await serve();
      final p = ServerProfile.parse(
        id: 'p1',
        name: 'T',
        kind: ServiceKind.sonarr,
        address: s.origin.toString(),
        pathPrefix: '/sonarr',
        allowCleartext: true,
      ).valueOrNull!;
      await factory().create(p).get<Object>('/api/v3/x');
      expect(s.seen.single.uri.path, '/sonarr/api/v3/x');
    });
  });

  group('origin lock', () {
    test('requests to another origin are refused', () async {
      final s = await serve();
      final other = await serve();
      final dio = factory().create(s.profile(allowCleartext: true));
      final err = await _failure(dio.get<Object>('${other.origin}/api'));
      expect(err.category, ErrorCategory.redirectRefused);
      expect(other.seen, isEmpty);
    });
  });

  group('redirects (SRV-08)', () {
    test('same-origin redirect keeps credentials, relative Location', () async {
      final s = await serve(
        handler: (r) {
          if (r.uri.path == '/start') {
            r.response
              ..statusCode = 302
              ..headers.set('location', '/final?x=1');
          } else {
            r.response.write('{}');
          }
        },
      );
      final dio = factory().create(s.profile(allowCleartext: true));
      final r = await dio.get<Object>(
        '/start',
        options: Options(headers: {'X-Api-Key': 'test-key-0000'}),
      );
      expect(r.statusCode, 200);
      expect(s.seen.map((e) => e.uri.toString()), ['/start', '/final?x=1']);
      expect(s.seen.last.headers['x-api-key'], 'test-key-0000');
    });

    test('cross-host redirect is followed with credentials stripped', () async {
      final target = await serve();
      final s = await serve(
        handler: (r) {
          r.response
            ..statusCode = 302
            ..headers.set(
              'location',
              'http://localhost:${target.port}/landing',
            );
        },
      );
      final dio = factory().create(s.profile(allowCleartext: true));
      final err = await _failure(
        dio.get<Object>(
          '/start',
          options: Options(
            headers: {
              'Authorization': 'Bearer test-token-0000',
              'X-Api-Key': 'test-key-0000',
              'Cookie': 'SID=test-session',
              'X-Custom-Gateway': 'test-secret',
              'Accept': 'application/json',
            },
          ),
        ),
      );
      // The target is http on another host: cleartext on a foreign host.
      expect(err.category, ErrorCategory.redirectRefused);
      expect(target.seen, isEmpty);
    });

    test(
      'https cross-origin redirect strips auth, keeps safe headers',
      () async {
        final cert = certs.selfSigned();
        final targetCert = certs.selfSigned();
        final target = await serve(cert: targetCert);
        final s = await serve(
          cert: cert,
          handler: (r) {
            r.response
              ..statusCode = 307
              ..headers.set('location', '${target.origin}/landing');
          },
        );
        // Trust both certificates for this profile's connections.
        final pins = InMemoryPinStore();
        for (final (srv, c) in [(s, cert), (target, targetCert)]) {
          final key = PinKey(
            profileId: 'p1',
            host: '127.0.0.1',
            port: srv.port,
          );
          final fp = CertificateFingerprint.parse(c.sha256Hex);
          await pins.write(
            key,
            fp,
            UserPinConfirmation.userAccepted(key: key, fingerprint: fp),
          );
        }
        final dio = factory(pins: pins).create(s.profile());
        final r = await dio.get<Object>(
          '/start',
          options: Options(
            headers: {
              'Authorization': 'Bearer test-token-0000',
              'X-Api-Key': 'test-key-0000',
              'Cookie': 'SID=test-session',
              'X-Custom-Gateway': 'test-secret',
              'Accept': 'application/json',
            },
          ),
        );
        expect(r.statusCode, 200);
        expect(s.seen.single.headers['x-api-key'], 'test-key-0000');
        final landed = target.seen.single;
        expect(landed.uri.path, '/landing');
        for (final h in [
          'authorization',
          'x-api-key',
          'cookie',
          'x-custom-gateway',
        ]) {
          expect(landed.headers, isNot(contains(h)), reason: h);
        }
        expect(landed.headers['accept'], 'application/json');
      },
    );

    test('https -> http redirect is refused', () async {
      final plain = await serve();
      final (s, _, dio) = await tlsServer(
        handler: (r) {
          r.response
            ..statusCode = 301
            ..headers.set('location', '${plain.origin}/x');
        },
      );
      final err = await _failure(dio.get<Object>('/start'));
      expect(err.category, ErrorCategory.redirectRefused);
      expect(plain.seen, isEmpty);
      expect(s.seen, hasLength(1));
    });

    test('redirect loops are capped', () async {
      final s = await serve(
        handler: (r) {
          r.response
            ..statusCode = 302
            ..headers.set('location', '/loop');
        },
      );
      final dio = factory().create(s.profile(allowCleartext: true));
      final err = await _failure(dio.get<Object>('/loop'));
      expect(err.category, ErrorCategory.redirectRefused);
      expect(s.seen.length, lessThanOrEqualTo(6));
    });

    test('POST + 303 becomes a body-less GET; POST + 307 is refused', () async {
      final s = await serve(
        handler: (r) {
          if (r.uri.path == '/see-other') {
            r.response
              ..statusCode = 303
              ..headers.set('location', '/done');
          } else if (r.uri.path == '/temp') {
            r.response
              ..statusCode = 307
              ..headers.set('location', '/done');
          } else {
            r.response.write('{}');
          }
        },
      );
      final dio = factory().create(s.profile(allowCleartext: true));
      await dio.post<Object>('/see-other', data: 'a=b');
      expect(s.seen.last.method, 'GET');
      final err = await _failure(dio.post<Object>('/temp', data: 'a=b'));
      expect(err.category, ErrorCategory.redirectRefused);
    });
  });

  group('limits', () {
    test('a body over the limit fails with response_too_large', () async {
      final s = await serve(handler: (r) => r.response.write('x' * 5000));
      final dio = factory(limits: const HttpLimits(maxResponseBytes: 1000))
          .create(s.profile(allowCleartext: true));
      final err = await _failure(dio.get<Object>('/big'));
      expect(err.category, ErrorCategory.responseTooLarge);
    });

    test('a streamed (chunked) body over the limit is aborted', () async {
      final s = await serve(
        handler: (r) async {
          r.response.bufferOutput = false;
          for (var i = 0; i < 20; i++) {
            r.response.add(List.filled(500, 120));
            await r.response.flush();
          }
        },
      );
      final dio = factory(limits: const HttpLimits(maxResponseBytes: 2000))
          .create(s.profile(allowCleartext: true));
      final err = await _failure(dio.get<Object>('/stream'));
      expect(err.category, ErrorCategory.responseTooLarge);
    });

    test('a per-request override allows larger bodies (images)', () async {
      final s = await serve(
        handler: (r) => r.response.add(List.filled(5000, 1)),
      );
      final dio = factory(limits: const HttpLimits(maxResponseBytes: 1000))
          .create(s.profile(allowCleartext: true));
      final r = await dio.get<List<int>>(
        '/img',
        options: Options(
          responseType: ResponseType.bytes,
          extra: {maxResponseBytesKey: 10000},
        ),
      );
      expect(r.data, hasLength(5000));
    });

    test('defaults: 16 MiB body cap and a total request deadline', () {
      const limits = HttpLimits();
      expect(limits.maxResponseBytes, 16 * 1024 * 1024);
      expect(limits.requestDeadline, greaterThan(limits.receiveTimeout));
    });

    test('a slow-drip body is cut off by the total deadline, although every '
        'chunk arrives within the receive timeout', () async {
      final s = await serve(
        handler: (r) async {
          r.response.bufferOutput = false;
          for (var i = 0; i < 100; i++) {
            r.response.add([120]);
            await r.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        },
      );
      final dio = factory(
        limits: const HttpLimits(
          receiveTimeout: Duration(seconds: 30),
          requestDeadline: Duration(milliseconds: 600),
        ),
      ).create(s.profile(allowCleartext: true));
      final watch = Stopwatch()..start();
      final err = await _failure(dio.get<Object>('/drip'));
      expect(err.category, ErrorCategory.timeout);
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    });

    test(
      'a server that never answers is cut off by the total deadline',
      () async {
        final s = await serve(
          handler: (r) => Future<void>.delayed(const Duration(seconds: 5)),
        );
        final dio = factory(
          limits: const HttpLimits(
            receiveTimeout: Duration(seconds: 30),
            requestDeadline: Duration(milliseconds: 300),
          ),
        ).create(s.profile(allowCleartext: true));
        final err = await _failure(dio.get<Object>('/hang'));
        expect(err.category, ErrorCategory.timeout);
      },
    );

    test('a fast response within the deadline is unaffected', () async {
      final s = await serve(handler: (r) => r.response.write('{"ok":true}'));
      final dio = factory(
        limits: const HttpLimits(requestDeadline: Duration(seconds: 5)),
      ).create(s.profile(allowCleartext: true));
      expect((await dio.get<Object>('/ok')).statusCode, 200);
    });

    test('a slow server maps to timeout', () async {
      final s = await serve(
        handler: (r) => Future<void>.delayed(const Duration(seconds: 2)),
      );
      final dio = factory(
        limits: const HttpLimits(receiveTimeout: Duration(milliseconds: 200)),
      ).create(s.profile(allowCleartext: true));
      final err = await _failure(dio.get<Object>('/slow'));
      expect(err.category, ErrorCategory.timeout);
    });

    test('defaults are sane', () {
      const l = HttpLimits();
      expect(l.maxResponseBytes, 16 * 1024 * 1024);
      expect(l.maxRedirects, 5);
      expect(l.connectTimeout, greaterThan(Duration.zero));
    });
  });

  group('images use the same factory (no key in URLs)', () {
    test('key travels in a header, bytes come back, pin applies', () async {
      final (s, _, dio) = await tlsServer(
        handler: (r) {
          r.response
            ..headers.contentType = ContentType('image', 'png')
            ..add([0x89, 0x50, 0x4e, 0x47]);
        },
      );
      final r = await dio.get<List<int>>(
        '/MediaCover/1/poster.jpg',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'X-Api-Key': 'test-key-0000'},
        ),
      );
      expect(r.data, [0x89, 0x50, 0x4e, 0x47]);
      final seen = s.seen.single;
      expect(seen.headers['x-api-key'], 'test-key-0000');
      expect(seen.uri.toString(), isNot(contains('test-key-0000')));
      expect(seen.uri.hasQuery, isFalse);
    });

    test(
      'an image server presenting an unpinned cert is not contacted',
      () async {
        final s = await serve(cert: certs.selfSigned());
        final dio = factory().create(s.profile());
        final err = await _failure(
          dio.get<List<int>>(
            '/poster.jpg',
            options: Options(responseType: ResponseType.bytes),
          ),
        );
        expect(err, isA<CertificateDecisionRequired>());
        expect(s.seen, isEmpty);
      },
    );
  });
}
