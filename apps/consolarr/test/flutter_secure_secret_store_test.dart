// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/storage/flutter_secure_secret_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingStorage extends FlutterSecureStorage {
  const _ThrowingStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'keystore', message: 'key invalidated');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trips, deletes and clears values', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = FlutterSecureSecretStore();
    await store.write('a', '1');
    await store.write('b', '2');
    expect(await store.read('a'), '1');
    await store.delete('a');
    expect(await store.read('a'), isNull);
    await store.deleteAll();
    expect(await store.read('b'), isNull);
  });

  test('a Keystore failure reads as a missing secret, never throws', () async {
    final store = FlutterSecureSecretStore(storage: const _ThrowingStorage());
    expect(await store.read('a'), isNull);
  });
}
