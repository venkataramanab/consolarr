// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:security/src/pin_key.dart';
import 'package:security/src/pin_store.dart';
import 'package:security/src/secret_store.dart';

/// Keeps secrets in memory only. For tests and previews.
class InMemorySecretStore implements SecretStore {
  InMemorySecretStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  /// Simulates Keystore loss: forgets every value.
  void simulateKeystoreLoss() => _values.clear();

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}

/// Keeps pins in memory only. Enforces the [PinStore] confirmation contract.
class InMemoryPinStore implements PinStore {
  final Map<PinKey, CertificateFingerprint> _pins = {};

  @override
  Future<CertificateFingerprint?> read(PinKey key) async => _pins[key];

  @override
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  ) async {
    if (!confirmation.covers(key, fingerprint)) {
      throw ArgumentError('confirmation does not cover this key/fingerprint');
    }
    _pins[key] = fingerprint;
  }

  @override
  Future<void> clear(PinKey key, UserPinConfirmation confirmation) async {
    if (confirmation.key != key) {
      throw ArgumentError('confirmation does not cover this key');
    }
    _pins.remove(key);
  }
}
