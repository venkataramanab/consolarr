// SPDX-License-Identifier: GPL-3.0-or-later

/// `SecretStore` keys for one server's secrets. The database row references the
/// server only by id; the values never leave the secret store.
abstract final class ServerSecretKeys {
  static String apiKey(String serverId) => '$serverId/api_key';
  static String username(String serverId) => '$serverId/username';
  static String password(String serverId) => '$serverId/password';
  static String header(String serverId, String name) =>
      '$serverId/header/${name.toLowerCase()}';
}
