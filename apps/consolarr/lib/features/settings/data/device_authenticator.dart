// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:local_auth/local_auth.dart';

/// What the device offers for unlocking the app.
enum DeviceAuthSupport {
  /// A secure lock method (PIN, pattern, password or biometric) exists.
  available,

  /// The platform *answered* that no secure lock method is set up. Only a
  /// normally returned answer counts: an error is [indeterminate].
  noSecureLock,

  /// The platform could not be asked (an error, no UI). Retryable; never
  /// treated as "the credential was removed".
  indeterminate,
}

/// The outcome of one unlock prompt. Deliberately coarse: the app learns
/// nothing about why a credential failed beyond this.
enum DeviceAuthResult {
  success,

  /// The credential was wrong or the biometric did not match.
  failed,

  /// The user dismissed the prompt.
  canceled,

  /// The platform is rate limiting attempts.
  lockedOut,

  /// The platform reported that no device credential is set at all. The only
  /// result that can mean "the secure lock method was removed".
  noCredential,
}

/// The platform authenticator: biometric with fallback to the device
/// credential. There is no app PIN and no stored secret.
abstract interface class DeviceAuthenticator {
  Future<DeviceAuthSupport> support();

  /// Whether a biometric is enrolled (informational: the device credential is
  /// always the fallback).
  Future<bool> hasBiometrics();

  /// Shows the system prompt with [reason].
  Future<DeviceAuthResult> authenticate({required String reason});
}

/// [DeviceAuthenticator] on `local_auth` (Android BiometricPrompt).
class PlatformDeviceAuthenticator implements DeviceAuthenticator {
  PlatformDeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<DeviceAuthSupport> support() async {
    try {
      return await _auth.isDeviceSupported()
          ? DeviceAuthSupport.available
          : DeviceAuthSupport.noSecureLock;
    } on Object {
      // A transient failure must never look like a removed credential.
      return DeviceAuthSupport.indeterminate;
    }
  }

  @override
  Future<bool> hasBiometrics() async {
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<DeviceAuthResult> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? DeviceAuthResult.success : DeviceAuthResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.uiUnavailable ||
        LocalAuthExceptionCode.authInProgress => DeviceAuthResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => DeviceAuthResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet =>
          DeviceAuthResult.noCredential,
        // Includes `noBiometricsEnrolled` and `noBiometricHardware`: the
        // device credential still works, so the lock is not "removed".
        _ => DeviceAuthResult.failed,
      };
    } on Object {
      return DeviceAuthResult.failed;
    }
  }
}
