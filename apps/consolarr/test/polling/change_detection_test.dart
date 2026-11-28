// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/shared/polling/change_detection/change_detection.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

TrackedItem item(
  String key,
  TrackedState state, {
  TrackedSource source = TrackedSource.arrQueue,
  double progress = 0,
  String? title,
}) => TrackedItem(
  key: key,
  source: source,
  state: state,
  progress: progress,
  title: title,
);

ServiceSnapshot snap(List<TrackedItem> items, {String server = 's1'}) =>
    ServiceSnapshot(serverId: server, items: items);

void main() {
  group('diffSnapshots', () {
    test('queue item reaching completed emits queueItemCompleted', () {
      final events = diffSnapshots(
        snap([item('a', TrackedState.active)]),
        snap([item('a', TrackedState.completed)]),
      );
      expect(events.single.type, ChangeType.queueItemCompleted);
      expect(events.single.itemKey, 'a');
      expect(events.single.serverId, 's1');
    });

    test('failure emits downloadFailed for both sources', () {
      final events = diffSnapshots(
        snap([
          item('a', TrackedState.active),
          item('t', TrackedState.active, source: TrackedSource.torrent),
        ]),
        snap([
          item('a', TrackedState.failed),
          item('t', TrackedState.failed, source: TrackedSource.torrent),
        ]),
      );
      expect(events.map((e) => e.type), [
        ChangeType.downloadFailed,
        ChangeType.downloadFailed,
      ]);
    });

    test('a torrent that finishes emits torrentFinished', () {
      final events = diffSnapshots(
        snap([item('t', TrackedState.active, source: TrackedSource.torrent)]),
        snap([
          item('t', TrackedState.completed, source: TrackedSource.torrent),
        ]),
      );
      expect(events.single.type, ChangeType.torrentFinished);
    });

    test('an item that vanishes without a terminal state emits nothing', () {
      expect(
        diffSnapshots(snap([item('a', TrackedState.active)]), snap([])),
        isEmpty,
      );
    });

    test('an item already terminal in both snapshots emits nothing', () {
      expect(
        diffSnapshots(
          snap([item('a', TrackedState.completed)]),
          snap([item('a', TrackedState.completed)]),
        ),
        isEmpty,
      );
    });

    test('a null previous snapshot is a baseline and emits nothing', () {
      expect(
        diffSnapshots(null, snap([item('a', TrackedState.completed)])),
        isEmpty,
      );
    });

    test('new items are not events (only observed transitions are)', () {
      expect(
        diffSnapshots(snap([]), snap([item('a', TrackedState.completed)])),
        isEmpty,
      );
    });

    test('the title is carried but never printed or serialised', () {
      final e = diffSnapshots(
        snap([item('a', TrackedState.active, title: 'Secret Show S01E01')]),
        snap([item('a', TrackedState.failed, title: 'Secret Show S01E01')]),
      ).single;
      expect(e.title, 'Secret Show S01E01');
      expect(e.toString(), isNot(contains('Secret')));
      expect(e.toJson().toString(), isNot(contains('Secret')));
      expect(
        item('a', TrackedState.active, title: 'Secret').toString(),
        isNot(contains('Secret')),
      );
    });
  });

  group('ChangeLedger', () {
    ChangeEvent ev(String key, {String server = 's1'}) => ChangeEvent(
      type: ChangeType.queueItemCompleted,
      serverId: server,
      itemKey: key,
    );

    test('each item key fires at most once', () {
      final ledger = ChangeLedger(InMemoryChangeStore());
      expect(ledger.admit([ev('a'), ev('a'), ev('b')]), hasLength(2));
      expect(ledger.admit([ev('a')]), isEmpty);
      expect(ledger.admit([ev('a', server: 's2')]), hasLength(1));
    });

    test('is bounded: the oldest entries are forgotten', () {
      final store = InMemoryChangeStore(capacity: 3);
      final ledger = ChangeLedger(store);
      ledger.admit([for (var i = 0; i < 10; i++) ev('k$i')]);
      expect(store.length, 3);
      expect(ledger.admit([ev('k9')]), isEmpty);
      expect(ledger.admit([ev('k0')]), hasLength(1));
    });
  });

  group('PollCycle', () {
    PollTarget target(
      String id,
      Future<Result<SnapshotFetch>> Function() fetch,
    ) => PollTarget(serverId: id, kind: ServiceKind.sonarr, source: fetch);

    Future<Result<SnapshotFetch>> ok(List<TrackedItem> items) async =>
        Result.ok(SnapshotFetch(items));

    test('first snapshot is a baseline: no events', () async {
      final cycle = PollCycle();
      final r = await cycle.run([
        target('s1', () => ok([item('a', TrackedState.completed)])),
      ]);
      expect(r.events, isEmpty);
      expect(r.outcomes.single.status, PollStatus.baseline);
    });

    test(
      'second poll emits the transition, third does not repeat it',
      () async {
        final cycle = PollCycle();
        var state = TrackedState.active;
        final t = target('s1', () => ok([item('a', state)]));
        await cycle.run([t]);
        state = TrackedState.completed;
        final second = await cycle.run([t]);
        expect(second.events, hasLength(1));
        final third = await cycle.run([t]);
        expect(third.events, isEmpty);
      },
    );

    test(
      'a failed fetch keeps the previous snapshot and emits nothing',
      () async {
        final cycle = PollCycle();
        var mode = 0;
        final t = target('s1', () async {
          mode++;
          return switch (mode) {
            1 => Result.ok(SnapshotFetch([item('a', TrackedState.active)])),
            2 => const Result.err(AppError(ErrorCategory.networkUnreachable)),
            _ => Result.ok(SnapshotFetch([item('a', TrackedState.completed)])),
          };
        });
        await cycle.run([t]);
        final failed = await cycle.run([t]);
        expect(failed.events, isEmpty);
        expect(failed.outcomes.single.status, PollStatus.failed);
        // Recovery compares against the snapshot from before the failure.
        final back = await cycle.run([t]);
        expect(back.events.single.type, ChangeType.queueItemCompleted);
      },
    );

    test('a partial fetch never counts as everything vanished', () async {
      final cycle = PollCycle();
      var partial = false;
      final t = target(
        's1',
        () async => Result.ok(
          partial
              ? SnapshotFetch([], partial: true)
              : SnapshotFetch([item('a', TrackedState.active)]),
        ),
      );
      await cycle.run([t]);
      partial = true;
      final r = await cycle.run([t]);
      expect(r.events, isEmpty);
      expect(r.outcomes.single.status, PollStatus.failed);
    });

    test('a throwing source is an isolated failure', () async {
      final cycle = PollCycle();
      final r = await cycle.run([
        target('bad', () async => throw StateError('boom')),
        target('good', () => ok([item('a', TrackedState.active)])),
      ]);
      expect(r.outcomes.map((o) => o.status), [
        PollStatus.failed,
        PollStatus.baseline,
      ]);
    });

    test('one failing server does not touch a healthy one', () async {
      final cycle = PollCycle();
      var good = TrackedState.active;
      final targets = [
        target(
          'bad',
          () async => const Result.err(AppError(ErrorCategory.timeout)),
        ),
        target('good', () => ok([item('a', good)])),
      ];
      await cycle.run(targets);
      good = TrackedState.completed;
      final r = await cycle.run(targets);
      expect(r.events.single.serverId, 'good');
      expect(
        r.outcomes.where((o) => o.status == PollStatus.failed),
        hasLength(1),
      );
    });

    test('concurrency is bounded', () async {
      var running = 0;
      var peak = 0;
      final cycle = PollCycle(maxConcurrent: 3);
      await cycle.run([
        for (var i = 0; i < 10; i++)
          target('s$i', () async {
            running++;
            if (running > peak) peak = running;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            running--;
            return const Result.ok(SnapshotFetch([]));
          }),
      ]);
      expect(peak, 3);
    });

    test(
      'reports counts to the observer without any identifying value',
      () async {
        final seen = <(int, int, int)>[];
        final changes = <ChangeType>[];
        final cycle = PollCycle(
          onCycleFinished: (servers, failed, count) =>
              seen.add((servers, failed, count)),
          onChange: changes.add,
        );
        var s = TrackedState.active;
        final t = target('s1', () => ok([item('a', s)]));
        await cycle.run([t]);
        s = TrackedState.failed;
        await cycle.run([t]);
        expect(seen, [(1, 0, 0), (1, 0, 1)]);
        expect(changes, [ChangeType.downloadFailed]);
      },
    );
  });

  test('change_detection stays pure Dart (no Flutter imports)', () {
    final dir = Directory('lib/shared/polling/change_detection');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains('package:flutter')));
      expect(f.readAsStringSync(), isNot(contains('package:flutter_riverpod')));
    }
  });
}
