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
/// Every `write` leaves a non-secret marker in drift **before** it stores the
/// pin, so a failure or a kill between the two writes leaves a marker without
/// a pin (a mismatch, fail closed) and never a pin without a marker. If the
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
    if (pin != null) {
      // A pin saved before markers existed (schema 6): backfill it, so a later
      // Keystore loss cannot read as first use.
      if (!await _markers.isMarked(key.storageKey)) {
        await _markers.mark(key.storageKey);
      }
      return pin;
    }
    return await _markers.isMarked(key.storageKey) ? _unmatchable : null;
  }

  @override
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  ) async {
    await _markers.mark(key.storageKey);
    await _inner.write(key, fingerprint, confirmation);
  }

  @override
  Future<void> clear(PinKey key, UserPinConfirmation confirmation) async {
    await _inner.clear(key, confirmation);
    await _markers.unmark(key.storageKey);
  }
}
