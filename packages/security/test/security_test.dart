// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';

class _MapSecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  Future<void> deleteAll() async => _m.clear();
}

/// Reference implementation of the PinStore contract used by the tests.
class _MapPinStore implements PinStore {
  final _m = <PinKey, CertificateFingerprint>{};
  @override
  Future<CertificateFingerprint?> read(PinKey key) async => _m[key];
  @override
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  ) async {
    if (!confirmation.covers(key, fingerprint)) {
      throw ArgumentError('confirmation does not cover this pin');
    }
    _m[key] = fingerprint;
  }

  @override
  Future<void> clear(PinKey key, UserPinConfirmation confirmation) async {
    if (confirmation.key != key) {
      throw ArgumentError('confirmation does not cover this key');
    }
    _m.remove(key);
  }
}

class _PlainFactory implements SecureHttpClientFactory {
  @override
  Dio create(ServerProfile profile) =>
      Dio(BaseOptions(baseUrl: profile.address.toString()));
}

void main() {
  test('SecretStore contract is implementable and round-trips', () async {
    final SecretStore s = _MapSecretStore();
    await s.write('srv1/api_key', 'test-key-0000');
    expect(await s.read('srv1/api_key'), 'test-key-0000');
    await s.delete('srv1/api_key');
    expect(await s.read('srv1/api_key'), isNull);
    await s.write('a', '1');
    await s.deleteAll();
    expect(await s.read('a'), isNull);
  });

  test('SecureHttpClientFactory takes a ServerProfile and returns Dio', () {
    final profile = ServerProfile.parse(
      id: 'p',
      name: 'n',
      kind: ServiceKind.sonarr,
      address: 'https://sonarr.example/',
    ).valueOrNull!;
    final SecureHttpClientFactory f = _PlainFactory();
    expect(f.create(profile).options.baseUrl, profile.baseUri.toString());
  });

  group('PinKey', () {
    PinKey key({
      String id = 'p1',
      String host = 'nas.example',
      int port = 443,
    }) => PinKey(profileId: id, host: host, port: port);

    test('normalises host case, trailing dot and IPv6 brackets', () {
      expect(key(host: 'NAS.Example.'), key());
      expect(key(host: '[2001:db8::1]'), key(host: '2001:db8::1'));
      expect(key(host: ' nas.example '), key());
    });

    test('profile, host and port all matter', () {
      expect(key(id: 'p2'), isNot(key()));
      expect(key(host: 'other.example'), isNot(key()));
      expect(key(port: 8443), isNot(key()));
      expect({key(), key(host: 'NAS.EXAMPLE')}, hasLength(1));
    });

    test('storage key is injective for awkward ids', () {
      expect(
        key(id: 'a/b', host: 'c.example').storageKey,
        isNot(key(id: 'a', host: 'b/c.example'.split('/').last).storageKey),
      );
      expect(key(id: 'a/b').storageKey, isNot(contains('a/b')));
    });

    test('rejects invalid parts', () {
      expect(() => key(id: ''), throwsArgumentError);
      expect(() => key(id: 'a b'), throwsArgumentError);
      expect(() => key(host: ''), throwsArgumentError);
      expect(() => key(host: 'a/b'), throwsArgumentError);
      expect(() => key(host: 'u@h.example'), throwsArgumentError);
      expect(() => key(port: 0), throwsArgumentError);
      expect(() => key(port: 65536), throwsArgumentError);
    });

    test('forProfile uses the explicit port or the scheme default', () {
      ServerProfile profile(String address) => ServerProfile.parse(
        id: 'p1',
        name: 'n',
        kind: ServiceKind.sonarr,
        address: address,
      ).valueOrNull!;
      expect(PinKey.forProfile(profile('https://NAS.example/')).port, 443);
      expect(
        PinKey.forProfile(profile('https://nas.example:8443/x')).port,
        8443,
      );
      expect(PinKey.forProfile(profile('http://192.0.2.5/')).port, 80);
      expect(
        PinKey.forProfile(profile('https://[2001:db8::1]:9443/')),
        key(host: '2001:db8::1', port: 9443),
      );
    });

    test('toString does not leak the host', () {
      expect(
        key(host: 'secret-host.example').toString(),
        isNot(contains('secret')),
      );
    });
  });

  group('CertificateFingerprint', () {
    test('parses colon separated, upper-case input', () {
      final fp = CertificateFingerprint.parse(List.filled(32, 'AB').join(':'));
      expect(fp.hex, 'ab' * 32);
      expect(fp.display, List.filled(32, 'AB').join(':'));
    });

    test('rejects anything but 32 bytes of hex', () {
      for (final bad in ['', 'ab', 'zz' * 32, 'ab' * 31, 'ab' * 33]) {
        expect(() => CertificateFingerprint.parse(bad), throwsFormatException);
      }
    });

    test('toString does not print the whole fingerprint', () {
      expect(
        CertificateFingerprint.parse('ab' * 32).toString(),
        isNot(contains('ab' * 32)),
      );
    });
  });

  group('PinStore contract', () {
    final key = PinKey(profileId: 'p1', host: 'nas.example', port: 443);
    final other = PinKey(profileId: 'p1', host: 'nas.example', port: 8443);
    final fp = CertificateFingerprint.parse('ab' * 32);
    final fp2 = CertificateFingerprint.parse('cd' * 32);

    test('round-trips with a matching user confirmation', () async {
      final PinStore store = _MapPinStore();
      expect(await store.read(key), isNull);
      await store.write(
        key,
        fp,
        UserPinConfirmation.userAccepted(key: key, fingerprint: fp),
      );
      expect(await store.read(key), fp);
      expect(
        await store.read(other),
        isNull,
        reason: 'port is part of the key',
      );
      await store.clear(
        key,
        UserPinConfirmation.userAccepted(key: key, fingerprint: fp),
      );
      expect(await store.read(key), isNull);
    });

    test('a confirmation for another key or fingerprint is refused', () async {
      final PinStore store = _MapPinStore();
      final forOther = UserPinConfirmation.userAccepted(
        key: other,
        fingerprint: fp,
      );
      final forFp2 = UserPinConfirmation.userAccepted(
        key: key,
        fingerprint: fp2,
      );
      await expectLater(store.write(key, fp, forOther), throwsArgumentError);
      await expectLater(store.write(key, fp, forFp2), throwsArgumentError);
      expect(await store.read(key), isNull);

      await store.write(
        key,
        fp,
        UserPinConfirmation.userAccepted(key: key, fingerprint: fp),
      );
      await expectLater(store.clear(key, forOther), throwsArgumentError);
      expect(await store.read(key), fp);
    });
  });

  group('decidePin (checked on every connection)', () {
    final fp = CertificateFingerprint.parse('ab' * 32);
    final fp2 = CertificateFingerprint.parse('cd' * 32);

    test('matching pin is accepted whether or not the chain is valid', () {
      for (final chainValid in [true, false]) {
        expect(
          decidePin(presented: fp, pinned: fp, chainValid: chainValid),
          PinVerdict.pinMatch,
        );
      }
    });

    test('a mismatching pin blocks even when the chain is valid', () {
      for (final chainValid in [true, false]) {
        final v = decidePin(presented: fp2, pinned: fp, chainValid: chainValid);
        expect(v, PinVerdict.pinMismatch);
        expect(v.allowed, isFalse);
      }
    });

    test('no pin: platform-trusted passes, untrusted is refused', () {
      expect(
        decidePin(presented: fp, pinned: null, chainValid: true),
        PinVerdict.platformTrusted,
      );
      final v = decidePin(presented: fp, pinned: null, chainValid: false);
      expect(v, PinVerdict.unpinnedUntrusted);
      expect(v.allowed, isFalse, reason: 'callback returns false: no pin');
    });
  });
}
