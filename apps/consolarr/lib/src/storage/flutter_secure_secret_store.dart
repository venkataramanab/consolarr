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
///
/// **No silent reset.** The plugin's `resetOnError` defaults to true: on a
/// cipher error it deletes every key and then reads as empty, which would turn
/// a pinned self-signed server back into a first-use trust prompt. The store
/// is built with `resetOnError: false`, so such an error surfaces as
/// [SecretStoreUnavailable]. The only way to clear is the user-confirmed
/// "Reset secure storage" action (see `SecureStorageReset`).
///
/// **Why the reset has its own instance.** On Android every plugin call,
/// `deleteAll` included, first runs `initialize`, and with a lost Keystore key
/// and `resetOnError: false` that fails for every call, so a reset sent with
/// the normal options could never succeed. The reset therefore goes through a
/// second storage built with `resetOnError: true`, whose `initialize` runs
/// `deleteAllDataAndKeys`. Only [deleteAll] uses it.
///
/// Plugin 11.2.0 caveat (`FlutterSecureStorage.java`): the native instance is
/// shared per preferences name and key prefix, and it keeps the config of the
/// call that initialised it. After a reset the native instance in this
/// process therefore still carries `resetOnError: true` until the process
/// ends. The store is empty and has a fresh key then, and a pin that is lost
/// again still reads as a mismatch through the drift markers, never as first
/// use.
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore({
    FlutterSecureStorage? storage,
    FlutterSecureStorage? resetStorage,
  }) : _storage =
           storage ?? const FlutterSecureStorage(aOptions: androidOptions),
       _resetStorage =
           resetStorage ??
           const FlutterSecureStorage(aOptions: resetAndroidOptions);

  /// The Android options of every normal read and write.
  static const androidOptions = AndroidOptions(resetOnError: false);

  /// The Android options of the user-confirmed reset, and nothing else.
  static const resetAndroidOptions = AndroidOptions(resetOnError: true);

  final FlutterSecureStorage _storage;
  final FlutterSecureStorage _resetStorage;

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
      await _resetStorage.deleteAll();
    } on PlatformException {
      // The user asked for a reset: never report success when it failed.
      throw const SecretStoreUnavailable('keystore clear failed');
    }
  }
}
