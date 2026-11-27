// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:security/security.dart';

/// [SecretStore] on the platform keystore (`flutter_secure_storage`).
///
/// Secrets never touch preference files. App data (including this store) is
/// excluded from backups by the manifest rules, so secrets never leave the
/// device.
///
/// Keystore loss (a restored device, changed lock screen, wiped keys) makes
/// reads fail on Android. That is reported as [SecretStoreUnavailable], never
/// as "no secret": the pin store must fail closed, while the credential path
/// maps it to "needs credentials" (SRV-09).
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      throw const SecretStoreUnavailable('keystore read failed');
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      // Nothing readable is stored under a lost key; deleting is a no-op.
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } on PlatformException {
      // See delete().
    }
  }
}
