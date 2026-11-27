// SPDX-License-Identifier: GPL-3.0-or-later

/// Persists trust-on-first-use certificate pins (SRV-06).
///
/// A pin is the SHA-256 fingerprint of a server's certificate, keyed by
/// `host:port`. A mismatch blocks the connection until the user explicitly
/// re-trusts. Implementations arrive in W3.
abstract interface class PinStore {
  /// The pinned SHA-256 fingerprint (lower-case hex) for [hostPort], if any.
  Future<String?> read(String hostPort);

  /// Pins [sha256Fingerprint] for [hostPort]. Only called after the user has
  /// seen and accepted the fingerprint.
  Future<void> write(String hostPort, String sha256Fingerprint);

  /// Forgets the pin for [hostPort] (explicit re-trust flow).
  Future<void> clear(String hostPort);
}
