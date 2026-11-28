// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:security/security.dart';

/// Non-secret record of which pin keys have a pin. See [MarkedPinStore].
abstract interface class PinnedMarkers {
  Future<bool> isMarked(String pinKey);
  Future<void> mark(String pinKey);
  Future<void> unmark(String pinKey);
  Future<void> clear();
}

/// [PinnedMarkers] in the app database.
class DriftPinnedMarkers implements PinnedMarkers {
  DriftPinnedMarkers(this._db);

  final AppDatabase _db;

  @override
  Future<bool> isMarked(String pinKey) async =>
      await (_db.select(
        _db.pinnedMarkerRows,
      )..where((r) => r.pinKey.equals(pinKey))).getSingleOrNull() !=
      null;

  @override
  Future<void> mark(String pinKey) => _db
      .into(_db.pinnedMarkerRows)
      .insertOnConflictUpdate(PinnedMarkerRowsCompanion.insert(pinKey: pinKey));

  @override
  Future<void> unmark(String pinKey) => (_db.delete(
    _db.pinnedMarkerRows,
  )..where((r) => r.pinKey.equals(pinKey))).go();

  @override
  Future<void> clear() => _db.delete(_db.pinnedMarkerRows).go();
}

/// A [PinStore] that cannot be talked into a first-use prompt after the pin
/// disappeared.
///
/// Every successful `write` leaves a non-secret marker in drift. If the
/// marker exists but the secret store returns no pin (Keystore reset, wiped
/// data), the read returns a fingerprint no certificate can match, so the
/// connection is blocked and shown as a pin mismatch until the user
/// re-trusts explicitly. An unreadable store still throws
/// [SecretStoreUnavailable] (fail closed).
class MarkedPinStore implements PinStore {
  MarkedPinStore(this._inner, this._markers);

  final PinStore _inner;
  final PinnedMarkers _markers;

  static final _unmatchable = CertificateFingerprint.parse('0' * 64);

  @override
  Future<CertificateFingerprint?> read(PinKey key) async {
    final pin = await _inner.read(key);
    if (pin != null) return pin;
    return await _markers.isMarked(key.storageKey) ? _unmatchable : null;
  }

  @override
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  ) async {
    await _inner.write(key, fingerprint, confirmation);
    await _markers.mark(key.storageKey);
  }

  @override
  Future<void> clear(PinKey key, UserPinConfirmation confirmation) async {
    await _inner.clear(key, confirmation);
    await _markers.unmark(key.storageKey);
  }
}
