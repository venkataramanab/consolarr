// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/data/torrents_repository.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final now = DateTime.utc(2026);

  test('combines torrents and transfer info', () async {
    final repo = TorrentsRepository(
      FakeTorrentClient(torrents: [sampleTorrent(1)]),
      clock: () => now,
    );
    final snapshot = (await repo.fetch()).valueOrNull!;
    expect(snapshot.torrents, hasLength(1));
    expect(snapshot.transfer!.dlSpeed, 1536);
    expect(snapshot.transferError, isNull);
    expect(snapshot.fetchedAt, now);
  });

  test('a failing torrent list fails the snapshot with its category', () async {
    final client = FakeTorrentClient()..failTorrents(ErrorCategory.authFailed);
    final r = await TorrentsRepository(client).fetch();
    expect(r.errorOrNull!.category, ErrorCategory.authFailed);
  });

  test('a failing transfer call only makes the snapshot partial', () async {
    final client = FakeTorrentClient(torrents: [sampleTorrent(1)])
      ..failTransfer();
    final snapshot = (await TorrentsRepository(client).fetch()).valueOrNull!;
    expect(snapshot.torrents, hasLength(1));
    expect(snapshot.transfer, isNull);
    expect(snapshot.transferError!.category, ErrorCategory.serverError);
  });
}
