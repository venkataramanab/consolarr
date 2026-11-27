// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:security/src/pin_key.dart';
import 'package:security/src/pin_store.dart';

/// What the user is shown (and what a pin is made from) for one certificate.
///
/// Built from the DER encoding the server presented; never from user input.
final class CertificateDetails {
  const CertificateDetails({
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
  });

  /// SHA-256 of the DER encoding.
  final CertificateFingerprint fingerprint;
  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;

  bool isExpiredAt(DateTime now) => now.isAfter(notAfter);
  bool isNotYetValidAt(DateTime now) => now.isBefore(notBefore);

  @override
  bool operator ==(Object other) =>
      other is CertificateDetails &&
      other.fingerprint == fingerprint &&
      other.subject == subject &&
      other.issuer == issuer &&
      other.notBefore == notBefore &&
      other.notAfter == notAfter;

  @override
  int get hashCode =>
      Object.hash(fingerprint, subject, issuer, notBefore, notAfter);

  /// Omits subject and issuer (they can carry host names).
  @override
  String toString() => 'CertificateDetails($fingerprint)';
}

/// First contact with an untrusted (for example self-signed) certificate.
///
/// The UI shows the trust sheet for [certificate]; only after the user accepts
/// does it write a pin for [key] (SRV-06). Category `tls_untrusted`.
class CertificateDecisionRequired extends AppError {
  const CertificateDecisionRequired({
    required this.key,
    required this.certificate,
  }) : super(ErrorCategory.tlsUntrusted);

  final PinKey key;
  final CertificateDetails certificate;
}

/// The server presented an expired (or not yet valid) certificate that is not
/// pinned. Reported, never offered for trust. Category `tls_expired`.
class CertificateExpired extends AppError {
  const CertificateExpired({required this.key, required this.certificate})
    : super(ErrorCategory.tlsExpired);

  final PinKey key;
  final CertificateDetails certificate;
}

/// A pinned server presented a different certificate. Blocks until the user
/// explicitly re-trusts (SRV-06). Category `tls_pin_mismatch`.
class TlsPinMismatch extends AppError {
  const TlsPinMismatch({
    required this.key,
    required this.pinned,
    required this.presented,
  }) : super(ErrorCategory.tlsPinMismatch);

  final PinKey key;

  /// The fingerprint the user trusted before.
  final CertificateFingerprint pinned;

  /// What the server presented now.
  final CertificateDetails presented;
}
