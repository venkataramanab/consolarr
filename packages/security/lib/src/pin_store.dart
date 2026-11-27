// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:security/src/pin_key.dart';

/// SHA-256 fingerprint of a certificate's DER encoding, as 64 lower-case hex
/// characters.
final class CertificateFingerprint {
  CertificateFingerprint._(this.hex);

  /// Parses 64 hex characters, with optional `:` or space separators and any
  /// letter case. Throws [FormatException] otherwise.
  factory CertificateFingerprint.parse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[:\s]'), '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(cleaned)) {
      throw const FormatException('not a SHA-256 fingerprint');
    }
    return CertificateFingerprint._(cleaned);
  }

  /// Lower-case hex, no separators.
  final String hex;

  /// `AB:CD:...` form for showing to the user.
  String get display => [
    for (var i = 0; i < hex.length; i += 2)
      hex.substring(i, i + 2).toUpperCase(),
  ].join(':');

  @override
  bool operator ==(Object other) =>
      other is CertificateFingerprint && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => 'CertificateFingerprint(${hex.substring(0, 8)}...)';
}

/// Proof that the user looked at a certificate fingerprint for a specific
/// server and explicitly accepted it.
///
/// [PinStore.write] requires one, so no code path can create or replace a pin
/// without a user decision. A token is bound to the [key] and [fingerprint]
/// that were shown; a token for one server or one certificate is useless for
/// another.
///
/// **Only the confirmation UI may construct this**, directly after the user
/// pressed the accept button of a dialog that displayed
/// [CertificateFingerprint.display] (and, for a changed certificate, said so
/// prominently). The `consolarr-pin-confirmation-construction` Semgrep rule
/// rejects construction anywhere else outside tests.
final class UserPinConfirmation {
  /// See the class documentation before calling this.
  const UserPinConfirmation.userAccepted({
    required this.key,
    required this.fingerprint,
  });

  /// The server the user confirmed.
  final PinKey key;

  /// The fingerprint the user saw and accepted.
  final CertificateFingerprint fingerprint;

  /// Whether this confirmation covers exactly [forKey] and [forFingerprint].
  bool covers(PinKey forKey, CertificateFingerprint forFingerprint) =>
      key == forKey && fingerprint == forFingerprint;
}

/// Persists trust-on-first-use certificate pins (SRV-06).
///
/// Contract (W3 implementations and their tests must uphold all of it):
///  * **Reads are keyed by [PinKey]** (profile id, normalised host, explicit
///    port), never by a bare host string.
///  * **[write] requires a [UserPinConfirmation] that covers exactly the key
///    and fingerprint written**; otherwise it throws [ArgumentError] and
///    stores nothing. This applies to first pins and to replacing a pin.
///  * **[clear] is the explicit forget/re-trust step**; it also requires a
///    confirmation for the key (the fingerprint of the old pin is irrelevant).
///  * Pins are consulted on **every** connection, not only when platform
///    chain validation fails; see `decidePin`.
abstract interface class PinStore {
  /// The pinned fingerprint for [key], or null when none exists.
  Future<CertificateFingerprint?> read(PinKey key);

  /// Pins [fingerprint] for [key]. Throws [ArgumentError] unless
  /// [confirmation] covers exactly [key] and [fingerprint].
  Future<void> write(
    PinKey key,
    CertificateFingerprint fingerprint,
    UserPinConfirmation confirmation,
  );

  /// Forgets the pin for [key]. Throws [ArgumentError] unless
  /// [confirmation.key] equals [key].
  Future<void> clear(PinKey key, UserPinConfirmation confirmation);
}
