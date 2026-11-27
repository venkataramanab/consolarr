// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:torrent_clients/src/models.dart';
import 'package:torrent_clients/src/torrent_actions.dart';
import 'package:torrent_clients/src/torrent_capabilities.dart';

/// Common surface of the supported torrent clients.
///
/// Concrete clients implement this on top of `SecureHttpClientFactory`.
/// Server-supplied strings are plain text and must be validated before use.
abstract interface class TorrentClient implements TorrentActions {
  /// Which client this is: [ServiceKind.qbittorrent],
  /// [ServiceKind.transmission] or [ServiceKind.deluge].
  ServiceKind get kind;

  /// The controls this client (as currently detected) supports. May change
  /// after the first successful call (for example Deluge's label plugin).
  TorrentCapabilities get capabilities;

  /// Forgets the in-memory session (cookie, token). Called when the active
  /// server or its credentials change, and on dispose. Nothing is persisted.
  void forgetSession();

  /// Fetches the server version string; doubles as a connection test.
  ///
  /// Fails with `auth_failed`, `timeout`, `network_unreachable`,
  /// `unsupported_version`, etc. (see [ErrorCategory]).
  Future<Result<String>> fetchVersion();

  /// All torrents.
  Future<Result<List<Torrent>>> listTorrents();

  /// Global speeds and totals.
  Future<Result<TransferInfo>> transferInfo();
}
