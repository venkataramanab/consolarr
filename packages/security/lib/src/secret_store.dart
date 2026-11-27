// SPDX-License-Identifier: GPL-3.0-or-later

/// OS-protected storage for secrets (API keys, passwords, tokens).
///
/// Secrets never live in plain preference files and are excluded from device
/// backups (SRV-09). Keys are opaque ids such as `<serverId>/api_key`.
/// Implementations arrive in a later task; only the contract is fixed here.
abstract interface class SecretStore {
  /// Returns the secret stored under [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any existing value.
  Future<void> write(String key, String value);

  /// Removes the secret stored under [key].
  Future<void> delete(String key);

  /// Removes every secret owned by the app.
  Future<void> deleteAll();
}
