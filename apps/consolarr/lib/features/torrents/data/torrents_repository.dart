// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// One poll of the client: the torrents and, when it could be read, the
/// global transfer statistics.
class TorrentSnapshot {
  const TorrentSnapshot({
    required this.torrents,
    required this.fetchedAt,
    this.transfer,
    this.transferError,
  });

  final List<Torrent> torrents;
  final DateTime fetchedAt;

  /// `null` when the statistics call failed (partial result).
  final TransferInfo? transfer;
  final AppError? transferError;
}

/// Reads torrents and transfer statistics from a [TorrentClient].
///
/// The torrent list is the primary call: its failure fails the snapshot. A
/// failing statistics call only marks the snapshot partial (the speed header),
/// so one broken endpoint never hides the list.
class TorrentsRepository {
  TorrentsRepository(this._client, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final TorrentClient _client;
  final DateTime Function() _clock;

  Future<Result<TorrentSnapshot>> fetch() async {
    final torrents = await _client.listTorrents();
    if (torrents case Err<List<Torrent>>(:final error)) {
      return Result.err(error);
    }
    final list = torrents.valueOrNull!;
    final transfer = await _client.transferInfo();
    return Result.ok(
      TorrentSnapshot(
        torrents: list,
        fetchedAt: _clock(),
        transfer: transfer.valueOrNull,
        transferError: transfer.errorOrNull,
      ),
    );
  }
}
