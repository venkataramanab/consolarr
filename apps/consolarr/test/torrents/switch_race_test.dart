// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrent_detail_provider.dart';
import 'package:consolarr/features/torrents/application/torrent_limits_controller.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

TorrentDetail _detail(String name) => TorrentDetail(
  torrent: sampleTorrent(1, name: name),
  savePath: '/downloads/$name',
);

void main() {
  late FakeTorrentClient a;
  late FakeTorrentClient b;
  late FakeTorrentClient current;
  late ProviderContainer c;

  setUp(() {
    a = FakeTorrentClient()..detail = _detail('from-a');
    b = FakeTorrentClient()..detail = _detail('from-b');
    current = a;
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        testDatabaseOverride,
        torrentClientProvider.overrideWith((ref) async => current),
        clockProvider.overrideWithValue(() => fixedNow),
      ],
    );
    addTearDown(c.dispose);
  });

  Future<void> switchToB() async {
    current = b;
    c.invalidate(torrentClientProvider);
    await c.read(torrentClientProvider.future);
    await pumpEventQueue();
  }

  test(
    'detail: a refresh from the old client cannot overwrite the new one',
    () async {
      c.listen(torrentDetailProvider('hash1'), (_, _) {});
      await c.read(torrentDetailProvider('hash1').future);
      expect(
        c.read(torrentDetailProvider('hash1')).value!.savePath,
        '/downloads/from-a',
      );

      a.detailGate = Completer<void>();
      final stale = c.read(torrentDetailProvider('hash1').notifier).refresh();
      await pumpEventQueue();
      await switchToB();
      await c.read(torrentDetailProvider('hash1').future);
      expect(
        c.read(torrentDetailProvider('hash1')).value!.savePath,
        '/downloads/from-b',
      );

      a.detailGate!.complete();
      await stale;
      await pumpEventQueue();
      expect(
        c.read(torrentDetailProvider('hash1')).value!.savePath,
        '/downloads/from-b',
        reason: 'the late answer of the old client is dropped',
      );
    },
  );

  test(
    'detail: a failed refresh reports false (the poller backs off)',
    () async {
      c.listen(torrentDetailProvider('hash1'), (_, _) {});
      await c.read(torrentDetailProvider('hash1').future);
      a.detailError = const AppError(ErrorCategory.timeout);
      final ok = await c
          .read(torrentDetailProvider('hash1').notifier)
          .refresh();
      expect(ok, isFalse);
      expect(
        c.read(torrentDetailProvider('hash1')).value!.savePath,
        '/downloads/from-a',
      );
    },
  );

  test(
    'limits: an apply for the old client does not touch the new one',
    () async {
      c.listen(torrentLimitsProvider, (_, _) {});
      await c.read(torrentLimitsProvider.future);
      b.limits = const SpeedLimitsState(
        download: 5000,
        upload: 0,
        alternativeActive: false,
      );

      a.actionGate = Completer<void>();
      final stale = c
          .read(torrentLimitsProvider.notifier)
          .apply(download: 111, upload: 222);
      await pumpEventQueue();
      await switchToB();
      await c.read(torrentLimitsProvider.future);
      expect(c.read(torrentLimitsProvider).value!.limits.download, 5000);

      a.actionGate!.complete();
      await stale;
      await pumpEventQueue();
      final view = c.read(torrentLimitsProvider).value!;
      expect(
        view.limits.download,
        5000,
        reason: 'still the new server\'s value',
      );
      expect(view.applied, isFalse);
      expect(view.applying, isFalse);
    },
  );

  test('limits: the values come from a re-read after apply', () async {
    c.listen(torrentLimitsProvider, (_, _) {});
    await c.read(torrentLimitsProvider.future);
    a.limitRounding = 1000;
    await c
        .read(torrentLimitsProvider.notifier)
        .apply(download: 1024, upload: 0);
    expect(c.read(torrentLimitsProvider).value!.limits.download, 2000);
  });
}
