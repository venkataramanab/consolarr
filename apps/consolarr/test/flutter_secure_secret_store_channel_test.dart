// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/storage/flutter_secure_secret_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';

// A separate file: `setMockInitialValues` swaps the plugin's platform for the
// rest of a test file, and these tests need the real method-channel platform.
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('real plugin behaviour on a Keystore error', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            if (call.method == 'read') {
              throw PlatformException(code: 'keystore', message: 'bad cipher');
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('a platform error surfaces and nothing is deleted', () async {
      final store = FlutterSecureSecretStore();
      await expectLater(
        store.read('a'),
        throwsA(isA<SecretStoreUnavailable>()),
      );
      expect(calls.map((c) => c.method), ['read']);
      expect(
        calls.map((c) => c.method),
        isNot(anyOf(contains('delete'), contains('deleteAll'))),
      );
    });

    test('every normal call tells the plugin not to reset on error', () async {
      final store = FlutterSecureSecretStore();
      await store.write('a', '1');
      await store.delete('a');
      await expectLater(
        store.read('a'),
        throwsA(isA<SecretStoreUnavailable>()),
      );
      expect(calls, isNotEmpty);
      for (final c in calls) {
        final options = (c.arguments as Map)['options'] as Map;
        expect(options['resetOnError'], 'false', reason: c.method);
      }
    });

    test(
      'only the confirmed reset asks the plugin to reset on error',
      () async {
        final store = FlutterSecureSecretStore();
        await store.write('a', '1');
        await store.delete('a');
        await store.deleteAll();
        final byMethod = {
          for (final c in calls)
            c.method: ((c.arguments as Map)['options'] as Map)['resetOnError'],
        };
        expect(byMethod['deleteAll'], 'true');
        expect(byMethod['write'], 'false');
        expect(byMethod['delete'], 'false');
      },
    );

    test('a normal read after the reset is still fail-closed', () async {
      final store = FlutterSecureSecretStore();
      await store.deleteAll();
      calls.clear();
      await expectLater(
        store.read('a'),
        throwsA(isA<SecretStoreUnavailable>()),
      );
      final options = (calls.single.arguments as Map)['options'] as Map;
      expect(options['resetOnError'], 'false');
    });

    test('the default Android options are fail-closed', () {
      expect(
        FlutterSecureSecretStore.androidOptions.params['resetOnError'],
        'false',
      );
    });

    test('a failed clear is reported, not swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'deleteAll') {
              throw PlatformException(code: 'keystore');
            }
            return null;
          });
      await expectLater(
        FlutterSecureSecretStore().deleteAll(),
        throwsA(isA<SecretStoreUnavailable>()),
      );
    });
  });
}
