// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:consolarr/features/torrents/application/torrent_actions_controller.dart';
import 'package:consolarr/features/torrents/application/torrent_limits_controller.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

import '../servers/ui/support.dart' show RecordingAnalytics;
import 'support.dart';

const _hash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _secretMagnet =
    'magnet:?xt=urn:btih:$_hash&dn=Secret+Title&tr=https%3A%2F%2Ftracker.example%2Fa%3Fpasskey%3Dsecret-passkey';

void main() {
  late FakeTorrentClient client;
  late RecordingAnalytics analytics;
  late Breadcrumbs crumbs;
  late ProviderContainer c;

  setUp(() {
    client = FakeTorrentClient(
      torrents: [sampleTorrent(1, name: 'Secret Title')],
    );
    analytics = RecordingAnalytics();
    crumbs = Breadcrumbs();
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        testDatabaseOverride,
        torrentClientProvider.overrideWith((ref) async => client),
        analyticsProvider.overrideWithValue(analytics),
        breadcrumbsProvider.overrideWithValue(crumbs),
        clockProvider.overrideWithValue(() => fixedNow),
      ],
    );
    addTearDown(c.dispose);
    c.listen(torrentListProvider, (_, _) {});
    c.listen(torrentActionsProvider, (_, _) {});
  });

  group('actions', () {
    test(
      'pause marks the row, calls the client once, reports success',
      () async {
        await c.read(torrentListProvider.future);
        client.actionGate = Completer<void>();
        final f = c.read(torrentActionsProvider.notifier).pause('hash1');
        await pumpEventQueue();
        expect(
          c.read(torrentActionsProvider).rows['hash1'],
          PendingAction.pausing,
        );
        // A second tap on the same row is refused while it is pending.
        final second = await c
            .read(torrentActionsProvider.notifier)
            .pause('hash1');
        expect(second.isErr, isTrue);
        client.actionGate!.complete();
        expect((await f).isOk, isTrue);
        expect(c.read(torrentActionsProvider).rows, isEmpty);
        expect(client.calls.where((x) => x == 'pause'), hasLength(1));
        expect(analytics.events, contains('torrents_action'));
        expect(analytics.parameters.last, {
          'action': 'pause',
          'outcome': 'success',
        });
      },
    );

    test('a failure reverts the row and records the category only', () async {
      await c.read(torrentListProvider.future);
      client.actionError = const AppError(ErrorCategory.timeout);
      final r = await c.read(torrentActionsProvider.notifier).resume('hash1');
      expect(r.errorOrNull?.category, ErrorCategory.timeout);
      expect(c.read(torrentActionsProvider).rows, isEmpty);
      expect(analytics.parameters.last, {
        'action': 'resume',
        'outcome': 'failed',
      });
      expect(
        crumbs.entries.map((e) => e.line),
        contains('api_error timeout qbittorrent'),
      );
    });

    test('an unsupported action is its own outcome', () async {
      await c.read(torrentListProvider.future);
      client.actionError = const UnsupportedAction('delete');
      await c
          .read(torrentActionsProvider.notifier)
          .remove('hash1', deleteFiles: true);
      expect(analytics.parameters.last, {
        'action': 'remove_with_data',
        'outcome': 'unsupported',
      });
    });

    test('remove passes the delete flag through', () async {
      await c.read(torrentListProvider.future);
      await c
          .read(torrentActionsProvider.notifier)
          .remove('hash1', deleteFiles: false);
      expect(client.lastDeleteFiles, isFalse);
      await c
          .read(torrentActionsProvider.notifier)
          .remove('hash1', deleteFiles: true);
      expect(client.lastDeleteFiles, isTrue);
    });

    test('pause all and resume all track progress and one call each', () async {
      await c.read(torrentListProvider.future);
      client.actionGate = Completer<void>();
      final f = c.read(torrentActionsProvider.notifier).pauseAll([
        'a',
        'b',
        'c',
      ]);
      await pumpEventQueue();
      expect(c.read(torrentActionsProvider).bulk, BulkAction.pauseAll);
      expect(c.read(torrentActionsProvider).bulkCount, 3);
      client.actionGate!.complete();
      await f;
      expect(c.read(torrentActionsProvider).bulk, isNull);
      await c.read(torrentActionsProvider.notifier).resumeAll(['a']);
      expect(client.calls.where((x) => x == 'pause'), hasLength(1));
      expect(client.calls.where((x) => x == 'resume'), hasLength(1));
    });
  });

  group('add', () {
    test('a link is sent once, the event has enums only', () async {
      final ok = await c
          .read(addTorrentProvider.notifier)
          .addLink(
            _secretMagnet,
            const AddTorrentOptions(savePath: '/data/secret-path'),
          );
      expect(ok, isTrue);
      expect(client.addedLinks, [_secretMagnet]);
      expect(analytics.events, contains('torrents_added'));
      expect(analytics.parameters.last, {
        'source': 'magnet',
        'client': 'qbittorrent',
        'outcome': 'success',
      });
    });

    test('an invalid link is never sent', () async {
      c.listen(addTorrentProvider, (_, _) {});
      expect(
        await c
            .read(addTorrentProvider.notifier)
            .addLink('ftp://x.example/a', const AddTorrentOptions()),
        isFalse,
      );
      expect(client.addedLinks, isEmpty);
    });

    test(
      'nothing the user typed reaches events, breadcrumbs or state',
      () async {
        c.listen(addTorrentProvider, (_, _) {});
        client.actionError = const AppError(ErrorCategory.timeout);
        await c
            .read(addTorrentProvider.notifier)
            .addLink(
              _secretMagnet,
              const AddTorrentOptions(
                savePath: '/data/secret-path',
                category: 'secret-cat',
              ),
            );
        await c.read(addTorrentProvider.notifier).addFiles([
          PickedTorrentFile(
            name: 'secret-file.torrent',
            length: () async => 10,
            readBytes: () async =>
                Uint8List.fromList('d4:infod4:name1:aee'.codeUnits),
          ),
        ], const AddTorrentOptions());
        await c
            .read(torrentActionsProvider.notifier)
            .remove('hash1', deleteFiles: true);
        final all = [
          ...analytics.events,
          for (final p in analytics.parameters) ...p.values.map((v) => '$v'),
          ...crumbs.entries.map((e) => e.line),
        ].join(' ');
        for (final secret in [
          'secret-passkey',
          'Secret Title',
          _hash,
          'secret-path',
          'secret-cat',
          'secret-file',
          'tracker.example',
          'hash1',
        ]) {
          expect(all, isNot(contains(secret)));
        }
        // Every parameter is a closed enum code, never free text.
        for (final p in analytics.parameters) {
          for (final v in p.values) {
            expect('$v', matches(RegExp(r'^[a-z_]+$')));
          }
        }
      },
    );
  });

  group('limits', () {
    test('apply sends bytes and reports; alternative toggles', () async {
      c.listen(torrentLimitsProvider, (_, _) {});
      await c.read(torrentLimitsProvider.future);
      await c
          .read(torrentLimitsProvider.notifier)
          .apply(download: 1000, upload: 0);
      expect(client.lastLimits!.download, 1000);
      expect(analytics.parameters.last, {
        'client': 'qbittorrent',
        'outcome': 'success',
      });
      await c.read(torrentLimitsProvider.notifier).setAlternative(true);
      expect(
        c.read(torrentLimitsProvider).value!.limits.alternativeActive,
        isTrue,
      );
    });

    test(
      'unsupported alternative limits disable the control, not the sheet',
      () async {
        c.listen(torrentLimitsProvider, (_, _) {});
        await c.read(torrentLimitsProvider.future);
        client.actionError = const UnsupportedAction('setAlternativeSpeed');
        await c.read(torrentLimitsProvider.notifier).setAlternative(true);
        final v = c.read(torrentLimitsProvider).value!;
        expect(v.altUnsupported, isTrue);
        expect(v.failure, isNull);
      },
    );
  });

  group('quiet polls back off before going offline', () {
    test(
      'two quiet failures keep the list as is, the third marks offline',
      () async {
        await c.read(torrentListProvider.future);
        final n = c.read(torrentListProvider.notifier);
        client.failTorrents(ErrorCategory.timeout);
        expect(await n.refresh(quiet: true), isFalse);
        expect(
          (c.read(torrentListProvider).value! as TorrentsData).offline,
          isFalse,
        );
        expect(await n.refresh(quiet: true), isFalse);
        expect(
          (c.read(torrentListProvider).value! as TorrentsData).offline,
          isFalse,
        );
        expect(await n.refresh(quiet: true), isFalse);
        expect(
          (c.read(torrentListProvider).value! as TorrentsData).offline,
          isTrue,
        );
        expect(n.consecutiveFailures, 3);
        client.setTorrents([sampleTorrent(1)]);
        expect(await n.refresh(quiet: true), isTrue);
        expect(n.consecutiveFailures, 0);
        expect(
          (c.read(torrentListProvider).value! as TorrentsData).offline,
          isFalse,
        );
      },
    );

    test(
      'a user refresh reports offline at once; auth failures are never hidden',
      () async {
        await c.read(torrentListProvider.future);
        final n = c.read(torrentListProvider.notifier);
        client.failTorrents(ErrorCategory.timeout);
        await n.refresh();
        expect(
          (c.read(torrentListProvider).value! as TorrentsData).offline,
          isTrue,
        );
        client.failTorrents(ErrorCategory.authFailed);
        await n.refresh(quiet: true);
        expect(c.read(torrentListProvider).hasError, isTrue);
      },
    );
  });
}
