// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

void main() {
  group('TorrentState.fromQBittorrent', () {
    const table = <String, TorrentState>{
      'error': TorrentState.error,
      'missingFiles': TorrentState.error,
      'uploading': TorrentState.seeding,
      'forcedUP': TorrentState.seeding,
      'stalledUP': TorrentState.seeding,
      'queuedUP': TorrentState.queued,
      'queuedDL': TorrentState.queued,
      'checkingUP': TorrentState.checking,
      'checkingDL': TorrentState.checking,
      'checkingResumeData': TorrentState.checking,
      'allocating': TorrentState.checking,
      'moving': TorrentState.checking,
      'downloading': TorrentState.downloading,
      'metaDL': TorrentState.downloading,
      'forcedMetaDL': TorrentState.downloading,
      'forcedDL': TorrentState.downloading,
      'stalledDL': TorrentState.stalled,
      'unknown': TorrentState.unknown,
      'somethingNew': TorrentState.unknown,
    };
    table.forEach((raw, expected) {
      test('$raw -> ${expected.name}', () {
        expect(TorrentState.fromQBittorrent(raw, progress: 0.5), expected);
      });
    });

    test('paused / stopped with unfinished progress is paused', () {
      for (final raw in ['pausedDL', 'pausedUP', 'stoppedDL', 'stoppedUP']) {
        expect(
          TorrentState.fromQBittorrent(raw, progress: 0.4),
          TorrentState.paused,
          reason: raw,
        );
      }
    });

    test('paused / stopped at 100% is finished', () {
      for (final raw in ['pausedDL', 'pausedUP', 'stoppedDL', 'stoppedUP']) {
        expect(
          TorrentState.fromQBittorrent(raw, progress: 1),
          TorrentState.finished,
          reason: raw,
        );
      }
    });

    test('a null state is unknown', () {
      expect(
        TorrentState.fromQBittorrent(null, progress: 0),
        TorrentState.unknown,
      );
    });
  });
}
