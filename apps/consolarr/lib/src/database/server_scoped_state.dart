// SPDX-License-Identifier: GPL-3.0-or-later

/// `AppStateRows` keys that belong to one server and must go with it. A
/// feature that stores per-server state there adds its key here; deleting the
/// server removes them all (`DriftServerRepository.delete`).
List<String> serverScopedStateKeys(String serverId) => [
  delugeHostStateKey(serverId),
];

/// The daemon host Deluge Web connected to for this server (a host id, never
/// an address).
String delugeHostStateKey(String serverId) => 'torrents.deluge_host.$serverId';
