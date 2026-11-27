// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class _FakeLocalAuth implements LocalAuthentication {
  Object? supportedResult = true;
  Object? biometricsResult = <BiometricType>[BiometricType.fingerprint];
  Object? authResult = true;
  int supportCalls = 0;

  @override
  Future<bool> isDeviceSupported() async {
    supportCalls++;
    final r = supportedResult;
    if (r is Exception) throw r;
    if (r is Error) throw r;
    return r! as bool;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    final r = biometricsResult;
    if (r is Exception) throw r;
    if (r is Error) throw r;
    return r! as List<BiometricType>;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const <dynamic>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    final r = authResult;
    if (r is Exception) throw r;
    if (r is Error) throw r;
    return r! as bool;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LocalAuthException _ex(LocalAuthExceptionCode code) =>
    LocalAuthException(code: code);

void main() {
  late _FakeLocalAuth fake;
  late PlatformDeviceAuthenticator auth;

  setUp(() {
    fake = _FakeLocalAuth();
    auth = PlatformDeviceAuthenticator(fake);
  });

  group('support', () {
    test('supported device is available', () async {
      expect(await auth.support(), DeviceAuthSupport.available);
    });

    test('a normal "not supported" answer means no secure lock', () async {
      fake.supportedResult = false;
      expect(await auth.support(), DeviceAuthSupport.noSecureLock);
    });

    test('an exception is indeterminate, never "removed"', () async {
      fake.supportedResult = PlatformException(code: 'boom');
      expect(await auth.support(), DeviceAuthSupport.indeterminate);
      fake.supportedResult = StateError('x');
      expect(await auth.support(), DeviceAuthSupport.indeterminate);
      fake.supportedResult = _ex(LocalAuthExceptionCode.uiUnavailable);
      expect(await auth.support(), DeviceAuthSupport.indeterminate);
    });
  });

  group('hasBiometrics', () {
    test('true, false and error', () async {
      expect(await auth.hasBiometrics(), isTrue);
      fake.biometricsResult = <BiometricType>[];
      expect(await auth.hasBiometrics(), isFalse);
      fake.biometricsResult = PlatformException(code: 'boom');
      expect(await auth.hasBiometrics(), isFalse);
    });
  });

  group('authenticate', () {
    Future<DeviceAuthResult> run() => auth.authenticate(reason: 'r');

    test('true is success, false is failed', () async {
      expect(await run(), DeviceAuthResult.success);
      fake.authResult = false;
      expect(await run(), DeviceAuthResult.failed);
    });

    const expected = <LocalAuthExceptionCode, DeviceAuthResult>{
      LocalAuthExceptionCode.userCanceled: DeviceAuthResult.canceled,
      LocalAuthExceptionCode.systemCanceled: DeviceAuthResult.canceled,
      LocalAuthExceptionCode.timeout: DeviceAuthResult.canceled,
      // Transient: retryable, never "the credential was removed".
      LocalAuthExceptionCode.uiUnavailable: DeviceAuthResult.canceled,
      LocalAuthExceptionCode.authInProgress: DeviceAuthResult.canceled,
      LocalAuthExceptionCode.temporaryLockout: DeviceAuthResult.lockedOut,
      LocalAuthExceptionCode.biometricLockout: DeviceAuthResult.lockedOut,
      // Only a real "no credential set" counts as removed.
      LocalAuthExceptionCode.noCredentialsSet: DeviceAuthResult.noCredential,
      // A device credential still works without a biometric.
      LocalAuthExceptionCode.noBiometricsEnrolled: DeviceAuthResult.failed,
      LocalAuthExceptionCode.noBiometricHardware: DeviceAuthResult.failed,
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
          DeviceAuthResult.failed,
      LocalAuthExceptionCode.userRequestedFallback: DeviceAuthResult.failed,
      LocalAuthExceptionCode.deviceError: DeviceAuthResult.failed,
      LocalAuthExceptionCode.unknownError: DeviceAuthResult.failed,
    };

    for (final code in LocalAuthExceptionCode.values) {
      test('maps ${code.name}', () async {
        expect(expected, contains(code), reason: 'unmapped code in the test');
        fake.authResult = _ex(code);
        expect(await run(), expected[code]);
      });
    }

    test('a generic platform exception is a retryable failure', () async {
      fake.authResult = PlatformException(code: 'boom');
      expect(await run(), DeviceAuthResult.failed);
      fake.authResult = StateError('x');
      expect(await run(), DeviceAuthResult.failed);
    });
  });
}
