// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
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

    test('a never-completing source times out beside healthy ones', () async {
      final cycle = PollCycle(
        targetTimeout: const Duration(milliseconds: 50),
        maxConcurrent: 2,
      );
      final hang = Completer<Result<SnapshotFetch>>();
      final r = await cycle
          .run([
            target('hang', () => hang.future),
            target('good', () => ok([item('a', TrackedState.active)])),
            target('good2', () => ok([item('b', TrackedState.active)])),
          ])
          .timeout(const Duration(seconds: 5));
      expect(r.outcomes.map((o) => o.status), [
        PollStatus.failed,
        PollStatus.baseline,
        PollStatus.baseline,
      ]);
      expect(r.outcomes.first.error, ErrorCategory.timeout);
      expect(r.outcomes.first.failure, PollFailure.timeout);
    });

    test('a timed-out server keeps its previous snapshot', () async {
      final cycle = PollCycle(targetTimeout: const Duration(milliseconds: 50));
      var s = TrackedState.active;
      var hang = false;
      final t = target(
        's1',
        () => hang
            ? Completer<Result<SnapshotFetch>>().future
            : ok([item('a', s)]),
      );
      await cycle.run([t]);
      hang = true;
      await cycle.run([t]);
      hang = false;
      s = TrackedState.failed;
      final r = await cycle.run([t]);
      expect(r.events.single.type, ChangeType.downloadFailed);
    });

    test(
      'a throwing source is reported as unexpected, not a parse error',
      () async {
        final r = await PollCycle().run([
          target('bad', () async => throw StateError('boom')),
        ]);
        final o = r.outcomes.single;
        expect(o.status, PollStatus.failed);
        expect(o.failure, PollFailure.unexpected);
        expect(o.error, isNull);
      },
    );

    test('a partial fetch is reported as partial', () async {
      final r = await PollCycle().run([
        target(
          'p',
          () async => const Result.ok(SnapshotFetch([], partial: true)),
        ),
      ]);
      expect(r.outcomes.single.failure, PollFailure.partial);
    });

    test('a source error keeps its own category', () async {
      final r = await PollCycle().run([
        target(
          'e',
          () async => const Result.err(AppError(ErrorCategory.authFailed)),
        ),
      ]);
      expect(r.outcomes.single.error, ErrorCategory.authFailed);
      expect(r.outcomes.single.failure, PollFailure.source);
    });

    test('concurrent runs are serialised: no shared-snapshot race', () async {
      final cycle = PollCycle();
      final gate = Completer<void>();
      var s = TrackedState.active;
      final t = target('s1', () async {
        await gate.future;
        return Result.ok(SnapshotFetch([item('a', s)]));
      });
      final first = cycle.run([t]);
      final second = cycle.run([t]);
      s = TrackedState.failed;
      gate.complete();
      final a = await first;
      final b = await second;
      // The first run is the baseline; the second diffs against it.
      expect(a.outcomes.single.status, PollStatus.baseline);
      expect(b.outcomes.single.status, PollStatus.updated);
      expect(a.events, isEmpty);
      expect(b.events.map((e) => e.itemKey).toSet().length, b.events.length);
    });

    test('a second run waits for the first to finish', () async {
      final cycle = PollCycle();
      final order = <String>[];
      final gate = Completer<void>();
      final slow = target('s1', () async {
        order.add('slow-start');
        await gate.future;
        order.add('slow-end');
        return ok([]);
      });
      final fast = target('s2', () {
        order.add('fast');
        return ok([]);
      });
      final first = cycle.run([slow]);
      final second = cycle.run([fast]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, ['slow-start']);
      gate.complete();
      await Future.wait([first, second]);
      expect(order, ['slow-start', 'slow-end', 'fast']);
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

  test('change_detection imports only pure-Dart libraries', () {
    // A real headless proof needs the layer outside the Flutter app package
    // (a larger move). Instead every import is checked against an exact
    // allowlist, so nothing that needs the engine (package:flutter, dart:ui,
    // material, riverpod, ...) can enter, directly or by a transitive import
    // of a sibling.
    final dir = Directory('lib/shared/polling/change_detection');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(
        disallowedChangeDetectionImports(f.readAsStringSync()),
        isEmpty,
        reason: f.path,
      );
    }
  });

  group('the import allowlist itself', () {
    test('rejects engine, UI and state libraries', () {
      for (final bad in [
        "import 'dart:ui';",
        "import 'dart:io';",
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/foundation.dart';",
        "import 'package:flutter_riverpod/flutter_riverpod.dart';",
        "import 'package:riverpod/riverpod.dart';",
        "import 'package:consolarr/shared/widgets/x.dart';",
        "import 'package:design_system/design_system.dart';",
        "export 'dart:ui';",
      ]) {
        expect(disallowedChangeDetectionImports(bad), isNotEmpty, reason: bad);
      }
    });

    test('accepts the pure libraries the layer uses', () {
      for (final good in [
        "import 'dart:async';",
        "import 'dart:collection';",
        "import 'package:core/core.dart';",
        "import 'package:consolarr/shared/polling/change_detection/diff.dart';",
        "import 'diff.dart';",
      ]) {
        expect(disallowedChangeDetectionImports(good), isEmpty, reason: good);
      }
    });
  });
}

/// The imports of [source] that a pure-Dart change-detection core may not use.
List<String> disallowedChangeDetectionImports(String source) {
  const allowedDart = {'async', 'collection', 'convert', 'math', 'typed_data'};
  const allowedPackages = {'core'};
  const ownPrefix = 'package:consolarr/shared/polling/change_detection/';
  final bad = <String>[];
  for (final m in RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  ).allMatches(source)) {
    final uri = m.group(1)!;
    final ok = switch (uri) {
      _ when uri.startsWith('dart:') => allowedDart.contains(uri.substring(5)),
      _ when uri.startsWith(ownPrefix) => true,
      _ when uri.startsWith('package:') => allowedPackages.contains(
        uri.substring(8).split('/').first,
      ),
      _ => !uri.contains(':'), // relative
    };
    if (!ok) bad.add(uri);
  }
  return bad;
}
