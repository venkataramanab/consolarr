// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

class _ActiveId extends Notifier<String> {
  @override
  String build() => 'a';
  void switchTo(String id) => state = id;
}

final _activeId = NotifierProvider<_ActiveId, String>(_ActiveId.new);

void main() {
  late Map<String, FakeTorrentClient> clients;

  setUp(() {
    clients = {
      'a': FakeTorrentClient(
        torrents: [sampleTorrent(1, name: 'Torrent On Server A')],
        transfer: const TransferInfo(
          dlSpeed: 111,
          upSpeed: 11,
          dlTotal: 0,
          upTotal: 0,
        ),
      ),
      'b': FakeTorrentClient(
        torrents: [sampleTorrent(2, name: 'Torrent On Server B')],
        transfer: const TransferInfo(
          dlSpeed: 222,
          upSpeed: 22,
          dlTotal: 0,
          upTotal: 0,
        ),
      ),
    };
  });

  List<Override> overrides() => [
    torrentClientProvider.overrideWith(
      (ref) async => clients[ref.watch(_activeId)],
    ),
    clockProvider.overrideWithValue(() => fixedNow),
  ];

  ProviderContainer container() {
    final c = ProviderContainer(retry: (_, _) => null, overrides: overrides());
    addTearDown(c.dispose);
    return c;
  }

  String firstName(AsyncValue<TorrentListState> v) =>
      (v.value! as TorrentsData).torrents.single.name;

  group('provider transitions', () {
    test('a switch reloads: loading, then the new server only', () async {
      final c = container();
      final sub = c.listen(torrentListProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(torrentListProvider.future);
      expect(firstName(c.read(torrentListProvider)), 'Torrent On Server A');

      clients['b']!.gate = Completer<void>();
      c.read(_activeId.notifier).switchTo('b');
      await pumpEventQueue();
      expect(c.read(torrentListProvider).isLoading, isTrue);

      clients['b']!.gate!.complete();
      await c.read(torrentListProvider.future);
      expect(firstName(c.read(torrentListProvider)), 'Torrent On Server B');
    });

    test(
      'a switch to a failing server is an error, not the old list',
      () async {
        final c = container();
        final sub = c.listen(torrentListProvider, (_, _) {});
        addTearDown(sub.close);
        await c.read(torrentListProvider.future);

        clients['b']!.failTorrents(ErrorCategory.authFailed);
        c.read(_activeId.notifier).switchTo('b');
        await pumpEventQueue();
        final state = c.read(torrentListProvider);
        expect(state.hasError, isTrue);
        expect((state.error! as AppError).category, ErrorCategory.authFailed);
      },
    );

    test('a poll that finishes after a switch is dropped', () async {
      final c = container();
      final sub = c.listen(torrentListProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(torrentListProvider.future);

      clients['a']!.gate = Completer<void>();
      final polling = c.read(torrentListProvider.notifier).refresh();
      await pumpEventQueue();
      clients['a']!.setTorrents([sampleTorrent(9, name: 'Late Answer A')]);

      c.read(_activeId.notifier).switchTo('b');
      await c.read(torrentListProvider.future);
      clients['a']!.gate!.complete();
      await polling;
      await pumpEventQueue();
      expect(firstName(c.read(torrentListProvider)), 'Torrent On Server B');
    });

    test('speed history forgets the previous server on a switch', () async {
      final c = container();
      final l1 = c.listen(torrentListProvider, (_, _) {});
      final l2 = c.listen(speedHistoryProvider, (_, _) {});
      addTearDown(l1.close);
      addTearDown(l2.close);
      await c.read(torrentListProvider.future);
      expect(c.read(speedHistoryProvider).single.down, 111);

      c.read(_activeId.notifier).switchTo('b');
      await c.read(torrentListProvider.future);
      await pumpEventQueue();
      expect(c.read(speedHistoryProvider).map((s) => s.down), [222]);
    });

    test('a poll disposed mid-flight does not write', () async {
      final c = container();
      final sub = c.listen(torrentListProvider, (_, _) {});
      await c.read(torrentListProvider.future);
      clients['a']!.gate = Completer<void>();
      final polling = c.read(torrentListProvider.notifier).refresh();
      await pumpEventQueue();
      sub.close();
      c.dispose();
      clients['a']!.gate!.complete();
      await expectLater(polling, completes);
    });
  });

  group('screen after a switch', () {
    testWidgets('shows a skeleton, then only the new server', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides(),
          child: screenAppFor(baseVariant),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Torrent On Server A'), findsOneWidget);

      clients['b']!.gate = Completer<void>();
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      scope.read(_activeId.notifier).switchTo('b');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Torrent On Server A'), findsNothing);
      expect(find.textContaining('Torrent On Server B'), findsNothing);

      clients['b']!.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Torrent On Server B'), findsOneWidget);
    });

    testWidgets('shows the error, not the old list, when the new server '
        'rejects the login', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides(),
          child: screenAppFor(baseVariant),
        ),
      );
      await tester.pumpAndSettle();
      clients['b']!.failTorrents(ErrorCategory.authFailed);
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .read(_activeId.notifier)
          .switchTo('b');
      await tester.pumpAndSettle();
      expect(find.textContaining('Torrent On Server A'), findsNothing);
    });
  });
}
