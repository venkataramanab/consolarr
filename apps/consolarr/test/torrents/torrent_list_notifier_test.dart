// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

ProviderContainer containerFor(Future<TorrentClient?> Function() client) {
  final c = ProviderContainer(
    overrides: [
      torrentClientProvider.overrideWith((ref) => client()),
      clockProvider.overrideWithValue(() => fixedNow),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('no configured client is the noServer state', () async {
    final c = containerFor(() async => null);
    final s = await c.read(torrentListProvider.future);
    expect(s, isA<TorrentsNoServer>());
  });

  test('loads torrents and flags a missing transfer as partial', () async {
    final client = FakeTorrentClient(torrents: [sampleTorrent(1)])
      ..failTransfer();
    final c = containerFor(() async => client);
    final s = await c.read(torrentListProvider.future) as TorrentsData;
    expect(s.torrents, hasLength(1));
    expect(s.transferUnavailable, isTrue);
    expect(s.offline, isFalse);
    expect(s.fetchedAt, fixedNow);
  });

  test('a failure without data is an AppError', () async {
    final client = FakeTorrentClient()..failTorrents(ErrorCategory.timeout);
    final c = containerFor(() async => client);
    final sub = c.listen(torrentListProvider, (_, _) {});
    await expectLater(
      c.read(torrentListProvider.future),
      throwsA(
        isA<AppError>().having(
          (e) => e.category,
          'category',
          ErrorCategory.timeout,
        ),
      ),
    );
    sub.close();
  });

  test('a failing refresh keeps the last data and goes offline', () async {
    final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
    final c = containerFor(() async => client);
    final sub = c.listen(torrentListProvider, (_, _) {});
    await c.read(torrentListProvider.future);
    client.failTorrents(ErrorCategory.networkUnreachable);
    await c.read(torrentListProvider.notifier).refresh();
    final s = c.read(torrentListProvider).value! as TorrentsData;
    expect(s.offline, isTrue);
    expect(s.torrents, hasLength(1));

    client
      ..setTorrents([sampleTorrent(1), sampleTorrent(2)])
      ..setTransfer(
        const TransferInfo(dlSpeed: 1, upSpeed: 1, dlTotal: 0, upTotal: 0),
      );
    await c.read(torrentListProvider.notifier).refresh();
    final back = c.read(torrentListProvider).value! as TorrentsData;
    expect(back.offline, isFalse);
    expect(back.torrents, hasLength(2));
    sub.close();
  });

  test('overlapping refreshes are coalesced', () async {
    final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
    final c = containerFor(() async => client);
    final sub = c.listen(torrentListProvider, (_, _) {});
    await c.read(torrentListProvider.future);
    final before = client.listCalls;
    client.gate = Completer<void>();
    final notifier = c.read(torrentListProvider.notifier);
    final a = notifier.refresh();
    final b = notifier.refresh();
    client.gate!.complete();
    await Future.wait([a, b]);
    expect(client.listCalls - before, 1);
    sub.close();
  });

  test('speed history gets one sample per successful poll only', () async {
    final client = FakeTorrentClient(torrents: [sampleTorrent(1)]);
    final c = containerFor(() async => client);
    final l1 = c.listen(torrentListProvider, (_, _) {});
    final l2 = c.listen(speedHistoryProvider, (_, _) {});
    await c.read(torrentListProvider.future);
    expect(c.read(speedHistoryProvider), [
      const SpeedSample(down: 1536, up: 512),
    ]);

    client.setTransfer(
      const TransferInfo(dlSpeed: 10, upSpeed: 20, dlTotal: 0, upTotal: 0),
    );
    await c.read(torrentListProvider.notifier).refresh();
    expect(
      c.read(speedHistoryProvider).last,
      const SpeedSample(down: 10, up: 20),
    );

    client.failTorrents(ErrorCategory.timeout);
    await c.read(torrentListProvider.notifier).refresh();
    expect(c.read(speedHistoryProvider), hasLength(2), reason: 'offline poll');
    l1.close();
    l2.close();
  });
}
