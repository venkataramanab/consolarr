// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';

import 'support/certs.dart';
import 'support/test_server.dart';

Future<Object> _failure(Future<Object?> call) async {
  try {
    await call;
  } on DioException catch (e) {
    return appErrorFromDio(e);
  }
  fail('expected a failure');
}

UserPinConfirmation _confirm(PinKey key, CertificateFingerprint fp) =>
    UserPinConfirmation.userAccepted(key: key, fingerprint: fp);

void main() {
  late CertFactory certs;
  late InMemoryPinStore pins;
  final servers = <TestServer>[];

  setUpAll(() => certs = CertFactory.create());
  tearDownAll(() => certs.dispose());
  setUp(() => pins = InMemoryPinStore());
  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
  });

  Future<TestServer> serve(TestCert cert) async {
    final s = await TestServer.start(cert: cert);
    servers.add(s);
    return s;
  }

  DefaultSecureHttpClientFactory factory({
    List<int>? roots,
    DateTime Function()? clock,
  }) => DefaultSecureHttpClientFactory(
    pins: pins,
    additionalTrustedRootsPem: roots,
    clock: clock,
  );

  Future<void> pin(TestServer s, TestCert c, {String id = 'p1'}) async {
    final key = PinKey.forProfile(s.profile(id: id));
    final fp = CertificateFingerprint.parse(c.sha256Hex);
    await pins.write(key, fp, _confirm(key, fp));
  }

  group('unpinned self-signed (TOFU)', () {
    test(
      'requires a decision carrying fingerprint, subject, issuer, validity',
      () async {
        final cert = certs.selfSigned(cn: 'nas.example', org: 'Example Org');
        final s = await serve(cert);
        final dio = factory().create(s.profile());

        final err = await _failure(dio.get<Object>('/api'));
        expect(err, isA<CertificateDecisionRequired>());
        final d = err as CertificateDecisionRequired;
        expect(d.category, ErrorCategory.tlsUntrusted);
        expect(d.certificate.fingerprint.hex, cert.sha256Hex);
        expect(d.certificate.subject, contains('nas.example'));
        expect(d.certificate.issuer, contains('Example Org'));
        expect(d.certificate.notAfter.isAfter(DateTime.now()), isTrue);
        expect(d.certificate.notBefore.isBefore(DateTime.now()), isTrue);
        expect(d.key, PinKey.forProfile(s.profile()));
        // The request never reached the application.
        expect(s.seen, isEmpty);
      },
    );

    test('after the user pins it, the same client connects', () async {
      final cert = certs.selfSigned();
      final s = await serve(cert);
      final dio = factory().create(s.profile());
      final err = await _failure(dio.get<Object>('/api'));
      final d = err as CertificateDecisionRequired;

      await pins.write(
        d.key,
        d.certificate.fingerprint,
        _confirm(d.key, d.certificate.fingerprint),
      );
      final r = await dio.get<Object>(
        '/api',
        options: Options(headers: {'X-Api-Key': 'test-key-0000'}),
      );
      expect(r.statusCode, 200);
      expect(s.seen.single.headers['x-api-key'], 'test-key-0000');
    });

    test('an expired unpinned certificate is reported, not offered', () async {
      final cert = certs.expiredSelfSigned();
      final s = await serve(cert);
      final err = await _failure(
        factory().create(s.profile()).get<Object>('/api'),
      );
      expect(err, isA<CertificateExpired>());
      expect((err as CertificateExpired).category, ErrorCategory.tlsExpired);
      expect(err.certificate.fingerprint.hex, cert.sha256Hex);
      expect(s.seen, isEmpty);
    });

    test(
      'a not-yet-valid certificate (clock in the past) is reported',
      () async {
        final cert = certs.selfSigned();
        final s = await serve(cert);
        final err = await _failure(
          factory(clock: () => DateTime.utc(2001))
              .create(s.profile())
              .get<Object>('/api'),
        );
        expect(err, isA<CertificateExpired>());
      },
    );
  });

  group('pinned', () {
    test('the pinned certificate is accepted, headers are sent', () async {
      final cert = certs.selfSigned();
      final s = await serve(cert);
      await pin(s, cert);
      final r = await factory()
          .create(s.profile())
          .get<Object>(
            '/api',
            options: Options(headers: {'X-Api-Key': 'test-key-0000'}),
          );
      expect(r.statusCode, 200);
      expect(s.seen, hasLength(1));
    });

    test(
      'a swapped self-signed certificate is blocked before any request',
      () async {
        final pinned = certs.selfSigned();
        final other = certs.selfSigned();
        final s = await serve(other);
        await pin(s, pinned);

        final err = await _failure(
          factory()
              .create(s.profile())
              .get<Object>(
                '/api',
                options: Options(headers: {'X-Api-Key': 'test-key-0000'}),
              ),
        );
        expect(err, isA<TlsPinMismatch>());
        final m = err as TlsPinMismatch;
        expect(m.category, ErrorCategory.tlsPinMismatch);
        expect(m.pinned.hex, pinned.sha256Hex);
        expect(m.presented.fingerprint.hex, other.sha256Hex);
        expect(
          s.seen,
          isEmpty,
          reason: 'no request bytes may reach the server',
        );
      },
    );

    test('a swapped CA-signed certificate is also blocked', () async {
      final ca = certs.ca();
      final pinned = certs.selfSigned();
      final impostor = ca.issue();
      final s = await serve(impostor);
      await pin(s, pinned);

      final err = await _failure(
        factory(roots: ca.pemBytes).create(s.profile()).get<Object>('/api'),
      );
      expect(err, isA<TlsPinMismatch>());
      expect(s.seen, isEmpty);
    });

    test('pinning a CA-valid certificate still pins its exact bytes', () async {
      final ca = certs.ca();
      final leaf = ca.issue();
      final renewed = ca.issue();
      final s = await serve(leaf);
      await pin(s, leaf);
      final dio = factory(roots: ca.pemBytes).create(s.profile());
      expect((await dio.get<Object>('/api')).statusCode, 200);

      // The server renews its certificate: blocked until explicit re-trust.
      await s.close();
      servers.remove(s);
      final s2 = await TestServer.start(cert: renewed);
      servers.add(s2);
      // Same profile id and port required: pin a key for s2's port.
      await pin(s2, leaf);
      final err = await _failure(
        factory(roots: ca.pemBytes).create(s2.profile()).get<Object>('/api'),
      );
      expect(err, isA<TlsPinMismatch>());
    });

    test(
      're-trust: clear + write the new pin unblocks the same client',
      () async {
        final old = certs.selfSigned();
        final fresh = certs.selfSigned();
        final s = await serve(fresh);
        await pin(s, old);
        final dio = factory().create(s.profile());
        final err = await _failure(dio.get<Object>('/api'));
        final m = err as TlsPinMismatch;

        await pins.clear(m.key, _confirm(m.key, m.pinned));
        await pins.write(
          m.key,
          m.presented.fingerprint,
          _confirm(m.key, m.presented.fingerprint),
        );
        expect((await dio.get<Object>('/api')).statusCode, 200);
      },
    );

    test('pins are per profile: another profile is not trusted', () async {
      final cert = certs.selfSigned();
      final s = await serve(cert);
      await pin(s, cert, id: 'other-profile');
      final err = await _failure(
        factory().create(s.profile()).get<Object>('/api'),
      );
      expect(err, isA<CertificateDecisionRequired>());
    });
  });

  group('CA-valid chains', () {
    test('accepted with normal validation and hostname verification', () async {
      final ca = certs.ca();
      final s = await serve(ca.issue());
      final r = await factory(roots: ca.pemBytes)
          .create(s.profile())
          .get<Object>('/api');
      expect(r.statusCode, 200);
    });

    test('a certificate for another host name is rejected', () async {
      final ca = certs.ca();
      final s = await serve(ca.issue(san: 'DNS:other.example'));
      final err = await _failure(
        factory(roots: ca.pemBytes).create(s.profile()).get<Object>('/api'),
      );
      expect(err, isA<CertificateDecisionRequired>());
      expect(s.seen, isEmpty);
    });

    test('an unknown CA is not trusted without roots', () async {
      final ca = certs.ca();
      final s = await serve(ca.issue());
      final err = await _failure(
        factory().create(s.profile()).get<Object>('/api'),
      );
      expect(err, isA<CertificateDecisionRequired>());
    });
  });
}
