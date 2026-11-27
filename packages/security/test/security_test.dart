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

class _MapPinStore implements PinStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String hostPort) async => _m[hostPort];
  @override
  Future<void> write(String hostPort, String fp) async => _m[hostPort] = fp;
  @override
  Future<void> clear(String hostPort) async => _m.remove(hostPort);
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

  test('PinStore contract is implementable and round-trips', () async {
    final PinStore p = _MapPinStore();
    await p.write('nas.example:443', 'ab' * 32);
    expect(await p.read('nas.example:443'), 'ab' * 32);
    await p.clear('nas.example:443');
    expect(await p.read('nas.example:443'), isNull);
  });

  test('SecureHttpClientFactory takes a ServerProfile and returns Dio', () {
    final profile = ServerProfile.parse(
      id: 'p',
      name: 'n',
      kind: ServiceKind.sonarr,
      address: 'https://sonarr.example/',
    ).valueOrNull!;
    final SecureHttpClientFactory f = _PlainFactory();
    expect(f.create(profile).options.baseUrl, 'https://sonarr.example/');
  });
}
