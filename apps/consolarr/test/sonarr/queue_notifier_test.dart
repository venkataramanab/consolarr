// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/sonarr/application/queue_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _choice = ArrQueueRemovalChoice(
  removeFromClient: true,
  blocklist: ArrBlocklistChoice.none,
);

ProviderContainer _container(
  ScriptedSonarrApi api, {
  Duration poll = const Duration(hours: 1),
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...sonarrTestOverrides(api),
      queuePollIntervalProvider.overrideWithValue(poll),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  c.listen(queueProvider, (_, _) {});
  return c;
}

void main() {
  test('loads the queue', () async {
    final api = ScriptedSonarrApi()
      ..queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(2)]);
    final c = _container(api);
    final state = await c.read(queueProvider.future) as QueueData;
    expect(state.items.map((i) => i.id), [1, 2]);
    expect(state.isOffline, isFalse);
  });

  test('empty queue, and 10,000 items', () async {
    final api = ScriptedSonarrApi();
    var c = _container(api);
    expect(((await c.read(queueProvider.future)) as QueueData).items, isEmpty);

    api.queueResult = Result.ok([
      for (var i = 1; i <= 10000; i++) fakeQueueItem(i),
    ]);
    c = _container(api);
    final sw = Stopwatch()..start();
    final data = await c.read(queueProvider.future) as QueueData;
    expect(data.items, hasLength(10000));
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('first load failure is a failure state with the category', () async {
    final api = ScriptedSonarrApi()
      ..queueResult = const Result.err(AppError(ErrorCategory.authFailed));
    final c = _container(api);
    final state = await c.read(queueProvider.future) as QueueFailure;
    expect(state.error.category, ErrorCategory.authFailed);
  });

  test('an unreachable refresh keeps the list as offline data', () async {
    final api = ScriptedSonarrApi()
      ..queueResult = Result.ok([fakeQueueItem(1)]);
    final c = _container(api);
    await c.read(queueProvider.future);
    api.queueResult = const Result.err(
      AppError(ErrorCategory.networkUnreachable),
    );
    await c.read(queueProvider.notifier).refresh();
    final state = c.read(queueProvider).value! as QueueData;
    expect(state.isOffline, isTrue);
    expect(state.items.single.id, 1);

    // Recovery clears the marker.
    api.queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(2)]);
    await c.read(queueProvider.notifier).refresh();
    final back = c.read(queueProvider).value! as QueueData;
    expect(back.isOffline, isFalse);
    expect(back.items, hasLength(2));
  });

  test('auth_failed on refresh is never hidden behind old data', () async {
    final api = ScriptedSonarrApi()
      ..queueResult = Result.ok([fakeQueueItem(1)]);
    final c = _container(api);
    await c.read(queueProvider.future);
    api.queueResult = const Result.err(AppError(ErrorCategory.authFailed));
    await c.read(queueProvider.notifier).refresh();
    expect(c.read(queueProvider).value, isA<QueueFailure>());
  });

  group('polling', () {
    test('refreshes on the interval and stops when disposed', () async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      final c = _container(api, poll: const Duration(milliseconds: 20));
      await c.read(queueProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final polled = api.count('queue');
      expect(polled, greaterThan(2));

      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.count('queue'), polled, reason: 'no calls after dispose');
    });

    test(
      'a server switch during the first load leaves no orphan timer',
      () async {
        final gate = Completer<void>();
        final first = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(1)])
          ..hook = (n) => n == 'queue' ? gate.future : Future.value();
        final second = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(2)]);
        final servers = SwitchableSonarr(first, second);
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            ...servers.overrides,
            queuePollIntervalProvider.overrideWithValue(
              const Duration(milliseconds: 20),
            ),
          ],
        );
        addTearDown(c.dispose);
        c.listen(queueProvider, (_, _) {});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(first.count('queue'), 1, reason: 'first load is in flight');
        servers.switchToSecond(c);
        final state = await c.read(queueProvider.future) as QueueData;
        expect(state.items.single.id, 2);
        // The first server's load now finishes; nothing may poll it afterwards.
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(first.count('queue'), 1);
        expect(
          second.count('queue'),
          greaterThan(2),
          reason: 'new server polls',
        );
        c.dispose();
        final polled = second.count('queue');
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(second.count('queue'), polled);
      },
    );

    test(
      'hiding the queue cancels the timer; showing it restarts it',
      () async {
        final api = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(1)]);
        final c = _container(api, poll: const Duration(milliseconds: 20));
        await c.read(queueProvider.future);
        final notifier = c.read(queueProvider.notifier);
        expect(notifier.isPolling, isTrue);
        notifier.visible = false;
        expect(notifier.isPolling, isFalse);
        notifier.visible = true;
        expect(notifier.isPolling, isTrue);
      },
    );

    test('polling skips its tick while the app is locked', () async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      final c = _container(api, poll: const Duration(milliseconds: 20));
      await c.read(queueProvider.future);
      c.read(testAppLockedProvider.notifier).locked = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final before = api.count('queue');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(api.count('queue'), before, reason: 'no request while locked');
      c.read(testAppLockedProvider.notifier).locked = false;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(api.count('queue'), greaterThan(before), reason: 'resumes');
    });

    test('a hidden queue does not poll', () async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      final c = _container(api, poll: const Duration(milliseconds: 20));
      await c.read(queueProvider.future);
      c.read(queueProvider.notifier).visible = false;
      final before = api.count('queue');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(api.count('queue'), before);
    });
  });

  group('a dropped removal is never success', () {
    test('a server switch while removing returns a defined error', () async {
      final gate = Completer<void>();
      final first = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)])
        ..hook = (n) => n == 'removeQueueItem' ? gate.future : Future.value();
      final second = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      final servers = SwitchableSonarr(first, second);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...servers.overrides,
          queuePollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(queueProvider, (_, _) {});
      await c.read(queueProvider.future);
      final removal = c.read(queueProvider.notifier).remove(1, _choice);
      await Future<void>.delayed(Duration.zero);
      servers.switchToSecond(c);
      await c.read(queueProvider.future);
      gate.complete();
      expect(await removal, QueueNotifier.droppedError);
      expect(second.count('removeQueueItem'), 0);
    });

    test(
      'a second removal of the same item while one runs is refused',
      () async {
        final gate = Completer<void>();
        final api = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(1)])
          ..hook = (n) => n == 'removeQueueItem' ? gate.future : Future.value();
        final c = _container(api);
        await c.read(queueProvider.future);
        final first = c.read(queueProvider.notifier).remove(1, _choice);
        await Future<void>.delayed(Duration.zero);
        expect(
          await c.read(queueProvider.notifier).remove(1, _choice),
          QueueNotifier.droppedError,
        );
        gate.complete();
        await first;
        expect(api.count('removeQueueItem'), 1);
      },
    );
  });

  group('remove', () {
    test('success drops the row, sends the choice, one request', () async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(2)]);
      final c = _container(api);
      await c.read(queueProvider.future);
      api.queueResult = Result.ok([fakeQueueItem(2)]);
      final error = await c
          .read(queueProvider.notifier)
          .remove(
            1,
            const ArrQueueRemovalChoice(
              removeFromClient: false,
              blocklist: ArrBlocklistChoice.blocklistAndSearch,
            ),
          );
      expect(error, isNull);
      expect(api.count('removeQueueItem'), 1);
      expect(api.sent.last, (1, false, ArrBlocklistChoice.blocklistAndSearch));
      final state = c.read(queueProvider).value! as QueueData;
      expect(state.items.map((i) => i.id), [2]);
    });

    test('a failure is returned and the item stays', () async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      final c = _container(api);
      await c.read(queueProvider.future);
      api.removeResult = const Result.err(AppError(ErrorCategory.serverError));
      final error = await c.read(queueProvider.notifier).remove(1, _choice);
      expect(error?.category, ErrorCategory.serverError);
      expect((c.read(queueProvider).value! as QueueData).items, hasLength(1));
    });

    test(
      'a failure after the server acted counts as success (no second submit)',
      () async {
        final api = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(2)]);
        final c = _container(api);
        await c.read(queueProvider.future);
        api.removeResult = const Result.err(
          AppError(ErrorCategory.networkUnreachable),
        );
        api.queueResult = Result.ok([fakeQueueItem(2)]);
        final error = await c.read(queueProvider.notifier).remove(1, _choice);
        expect(error, isNull);
        expect(api.count('removeQueueItem'), 1);
      },
    );

    test(
      'a second removal of the same item while in flight is ignored',
      () async {
        final gate = Completer<void>();
        final api = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(1)]);
        final c = _container(api);
        await c.read(queueProvider.future);
        api.hook = (name) =>
            name == 'removeQueueItem' ? gate.future : Future.value();
        final notifier = c.read(queueProvider.notifier);
        final first = notifier.remove(1, _choice);
        final second = notifier.remove(1, _choice);
        gate.complete();
        await Future.wait([first, second]);
        expect(api.count('removeQueueItem'), 1);
      },
    );

    test('is refused while offline (writes disabled)', () async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      final c = _container(api);
      await c.read(queueProvider.future);
      api.queueResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
      await c.read(queueProvider.notifier).refresh();
      final error = await c.read(queueProvider.notifier).remove(1, _choice);
      expect(error?.category, ErrorCategory.networkUnreachable);
      expect(api.count('removeQueueItem'), 0);
    });
  });
}
