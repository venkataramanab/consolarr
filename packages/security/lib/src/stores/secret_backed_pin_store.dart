// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:security/src/pin_key.dart';
import 'package:security/src/pin_store.dart';
import 'package:security/src/secret_store.dart';

/// Persists pins in the OS-protected [SecretStore] (tamper-resistant, excluded
/// from backups) under [PinKey.storageKey]. Enforces the confirmation contract.
class SecretBackedPinStore implements PinStore {
  SecretBackedPinStore(this._secrets);

  final SecretStore _secrets;

  static final _unmatchable = CertificateFingerprint.parse('0' * 64);

  @override
  Future<CertificateFingerprint?> read(PinKey key) async {
    final stored = await _secrets.read(key.storageKey);
    if (stored == null) return null;
    try {
      return CertificateFingerprint.parse(stored);
    } on FormatException {
      // A corrupt entry is still a pin: returning null would silently turn a
      // pinned server into an unpinned one. Return a value no certificate can
      // match, so the connection is blocked until the user re-trusts.
      return _unmatchable;
    }
  }

  @override
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  ) async {
    if (!confirmation.covers(key, fingerprint)) {
      throw ArgumentError('confirmation does not cover this key/fingerprint');
    }
    await _secrets.write(key.storageKey, fingerprint.hex);
  }

  @override
  Future<void> clear(PinKey key, UserPinConfirmation confirmation) async {
    if (confirmation.key != key) {
      throw ArgumentError('confirmation does not cover this key');
    }
    await _secrets.delete(key.storageKey);
  }
}
