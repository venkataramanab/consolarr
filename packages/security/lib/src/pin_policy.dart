// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:security/src/pin_store.dart';

/// Outcome of checking one TLS connection against the pin store.
enum PinVerdict {
  /// A pin exists and matches the presented certificate.
  pinMatch(allowed: true),

  /// No pin exists and the platform accepted the certificate chain.
  platformTrusted(allowed: true),

  /// A pin exists but the presented certificate differs: block, whatever the
  /// platform thinks of the chain (a valid chain from another CA is exactly
  /// what a targeted attack looks like). Surface `tls_pin_mismatch`.
  pinMismatch(allowed: false),

  /// No pin exists and the platform rejected the chain: block, and offer the
  /// trust-on-first-use dialog. Never silently trust (the bad-certificate
  /// callback returns false in this case).
  unpinnedUntrusted(allowed: false);

  const PinVerdict({required this.allowed});

  /// Whether the connection may proceed.
  final bool allowed;
}

/// The TOFU decision, as a pure function so it can be tested exhaustively.
///
/// **It must be evaluated for every TLS connection to a server profile, not
/// only when chain validation fails.** (the platform's bad-certificate
/// hook only runs for chains the platform rejects, so a W3 implementation must also
/// hook the connection-established path, e.g. dio's
/// `IOHttpClientAdapter.validateCertificate`, or pin through a
/// `SecurityContext`.) Otherwise a pinned server could be impersonated with a
/// certificate that chains to a system-trusted CA.
///
/// * [pinned] is `PinStore.read` for the connection's `PinKey` (null: none).
/// * [presented] is the SHA-256 of the leaf certificate the server sent.
/// * [chainValid] is whether platform validation (including hostname
///   verification) accepted the chain.
PinVerdict decidePin({
  required CertificateFingerprint presented,
  required CertificateFingerprint? pinned,
  required bool chainValid,
}) {
  if (pinned != null) {
    return pinned == presented ? PinVerdict.pinMatch : PinVerdict.pinMismatch;
  }
  return chainValid ? PinVerdict.platformTrusted : PinVerdict.unpinnedUntrusted;
}
