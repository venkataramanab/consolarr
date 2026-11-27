// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrent_actions_controller.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

void main() {
  late FakeTorrentClient a;
  late FakeTorrentClient b;
  late FakeTorrentClient current;
  late ProviderContainer c;

  setUp(() {
    a = FakeTorrentClient(torrents: [sampleTorrent(1), sampleTorrent(2)]);
    b = FakeTorrentClient(torrents: [sampleTorrent(3)]);
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
    c.listen(torrentListProvider, (_, _) {});
    c.listen(torrentActionsProvider, (_, _) {});
  });

  test(
    'a partial delete is reported and the list is refreshed anyway',
    () async {
      await c.read(torrentListProvider.future);
      final before = a.listCalls;
      a.actionError = PartialActionFailure(
        category: ErrorCategory.serverError,
        failed: const ['hash1', 'hash2'],
        total: 5,
      );
      final r = await c
          .read(torrentActionsProvider.notifier)
          .remove('hash1', deleteFiles: false);
      expect(r.errorOrNull, isA<PartialActionFailure>());
      expect((r.errorOrNull! as PartialActionFailure).failed, hasLength(2));
      expect(a.listCalls, greaterThan(before), reason: 'refresh on error too');
      expect(c.read(torrentActionsProvider).rows, isEmpty);
    },
  );

  test('a plain failure also refreshes the list', () async {
    await c.read(torrentListProvider.future);
    final before = a.listCalls;
    a.actionError = const AppError(ErrorCategory.timeout);
    await c.read(torrentActionsProvider.notifier).pause('hash1');
    expect(a.listCalls, greaterThan(before));
  });

  test(
    'a bulk started before a server switch cannot clear the new one',
    () async {
      await c.read(torrentListProvider.future);
      a.actionGate = Completer<void>();
      final stale = c.read(torrentActionsProvider.notifier).pauseAll(['hash1']);
      await pumpEventQueue();
      expect(c.read(torrentActionsProvider).bulk, BulkAction.pauseAll);

      // Switch the active server: the controller rebuilds and resets.
      current = b;
      c.invalidate(torrentClientProvider);
      await c.read(torrentClientProvider.future);
      await pumpEventQueue();
      expect(c.read(torrentActionsProvider).bulk, isNull);

      b.actionGate = Completer<void>();
      final fresh = c.read(torrentActionsProvider.notifier).resumeAll([
        'hash3',
      ]);
      await pumpEventQueue();
      expect(c.read(torrentActionsProvider).bulk, BulkAction.resumeAll);

      a.actionGate!.complete();
      await stale;
      await pumpEventQueue();
      expect(
        c.read(torrentActionsProvider).bulk,
        BulkAction.resumeAll,
        reason: 'the old server finishing must not reset the new bulk marker',
      );
      b.actionGate!.complete();
      await fresh;
      expect(c.read(torrentActionsProvider).bulk, isNull);
    },
  );
}
