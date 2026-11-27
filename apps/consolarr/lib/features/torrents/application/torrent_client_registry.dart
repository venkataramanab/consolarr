// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// What a client factory gets: the secure, already authenticated [dio], the
/// profile and the stored credentials (for clients that log in themselves).
class TorrentClientContext {
  const TorrentClientContext({
    required this.dio,
    required this.profile,
    required this.credentials,
    required this.onRowsSkipped,
    this.hostId,
    this.onHostConnected,
  });

  final Dio dio;
  final ServerProfile profile;
  final ServerCredentials credentials;

  /// Reports the number (only) of malformed rows a client skipped.
  final void Function(int skipped) onRowsSkipped;

  /// The daemon host remembered for this server (Deluge).
  final String? hostId;

  /// Remembers the daemon host the client connected to (Deluge).
  final void Function(String hostId)? onHostConnected;
}

typedef TorrentClientFactory = TorrentClient Function(TorrentClientContext c);

/// Torrent client factories per [ServiceKind]. A new client registers its
/// factory here (one line); nothing else switches on the kind.
///
/// The map order is the order in which the active server of each kind is
/// looked up, so it is also the priority when several kinds are configured.
final Map<ServiceKind, TorrentClientFactory> torrentClientFactories = {
  ServiceKind.qbittorrent: (c) => QBittorrentClient(
    dio: c.dio,
    username: c.profile.authMode == AuthMode.basic
        ? c.credentials.username
        : null,
    password: c.profile.authMode == AuthMode.basic
        ? c.credentials.password
        : null,
    onRowsSkipped: c.onRowsSkipped,
  ),
  ServiceKind.transmission: (c) => TransmissionClient(
    dio: c.dio,
    username: c.profile.authMode == AuthMode.basic
        ? c.credentials.username
        : null,
    password: c.profile.authMode == AuthMode.basic
        ? c.credentials.password
        : null,
    onRowsSkipped: c.onRowsSkipped,
  ),
  // Deluge Web has a password only; a username in the editor is ignored.
  ServiceKind.deluge: (c) => DelugeClient(
    dio: c.dio,
    password: c.profile.authMode == AuthMode.basic
        ? c.credentials.password
        : null,
    hostId: c.hostId,
    onHostConnected: c.onHostConnected,
    onRowsSkipped: c.onRowsSkipped,
  ),
};
