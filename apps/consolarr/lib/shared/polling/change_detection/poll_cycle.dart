// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/shared/polling/change_detection/change_event.dart';
import 'package:consolarr/shared/polling/change_detection/change_ledger.dart';
import 'package:consolarr/shared/polling/change_detection/diff.dart';
import 'package:consolarr/shared/polling/change_detection/tracked_item.dart';
import 'package:core/core.dart';

/// What a source returns. [partial] marks a fetch that may be missing items
/// (rows skipped, a page missing): it is never used as a snapshot.
class SnapshotFetch {
  const SnapshotFetch(this.items, {this.partial = false});

  final List<TrackedItem> items;
  final bool partial;
}

typedef SnapshotSource = Future<Result<SnapshotFetch>> Function();

/// One server to poll. Any source works: the layer needs no connection seam.
class PollTarget {
  const PollTarget({
    required this.serverId,
    required this.kind,
    required this.source,
  });

  final String serverId;
  final ServiceKind kind;
  final SnapshotSource source;
}

/// How one server fared in a cycle.
enum PollStatus { baseline, updated, failed }

class PollOutcome {
  const PollOutcome({required this.serverId, required this.status, this.error});

  final String serverId;
  final PollStatus status;

  /// The error category when [status] is [PollStatus.failed].
  final ErrorCategory? error;
}

class PollCycleResult {
  const PollCycleResult({required this.events, required this.outcomes});

  final List<ChangeEvent> events;
  final List<PollOutcome> outcomes;
}

/// Fetches every server independently (bounded concurrency), diffs against the
/// last good snapshot and returns the new events plus a per-server outcome.
///
/// * The first snapshot of a server is a baseline.
/// * A failed or partial fetch (or a throwing source) keeps the previous
///   snapshot: an error is never "everything vanished".
/// * One server's failure never touches another.
///
/// Nothing here schedules itself; the owner decides when to call [run].
class PollCycle {
  PollCycle({
    ChangeLedger? ledger,
    this.maxConcurrent = 4,
    this.onCycleFinished,
    this.onChange,
  }) : ledger = ledger ?? ChangeLedger(InMemoryChangeStore()),
       assert(maxConcurrent > 0);

  final ChangeLedger ledger;
  final int maxConcurrent;

  /// Counts only: servers, failed, changes.
  final void Function(int servers, int failed, int changes)? onCycleFinished;

  /// One call per new event, with its type only.
  final void Function(ChangeType type)? onChange;

  final Map<String, ServiceSnapshot> _last = {};

  /// Forgets the snapshot of a server (for example when it was removed).
  void forget(String serverId) => _last.remove(serverId);

  Future<PollCycleResult> run(List<PollTarget> targets) async {
    final outcomes = List<PollOutcome?>.filled(targets.length, null);
    final perTarget = List<List<ChangeEvent>>.filled(
      targets.length,
      <ChangeEvent>[],
    );
    var next = 0;

    Future<void> worker() async {
      while (next < targets.length) {
        final i = next++;
        final (outcome, events) = await _one(targets[i]);
        outcomes[i] = outcome;
        perTarget[i] = events;
      }
    }

    final workers = targets.length < maxConcurrent
        ? targets.length
        : maxConcurrent;
    await Future.wait([for (var w = 0; w < workers; w++) worker()]);

    // Admit in target order so the result does not depend on timing.
    final events = ledger.admit(perTarget.expand((e) => e));
    events.map((e) => e.type).forEach((t) => onChange?.call(t));
    final done = [for (final o in outcomes) o!];
    onCycleFinished?.call(
      done.length,
      done.where((o) => o.status == PollStatus.failed).length,
      events.length,
    );
    return PollCycleResult(events: events, outcomes: done);
  }

  Future<(PollOutcome, List<ChangeEvent>)> _one(PollTarget t) async {
    try {
      final result = await t.source();
      switch (result) {
        case Err(:final error):
          return (_failed(t, error.category), <ChangeEvent>[]);
        case Ok(:final value):
          if (value.partial) {
            return (_failed(t, ErrorCategory.parseError), <ChangeEvent>[]);
          }
          final snapshot = ServiceSnapshot(
            serverId: t.serverId,
            items: value.items,
          );
          final prev = _last[t.serverId];
          _last[t.serverId] = snapshot;
          return (
            PollOutcome(
              serverId: t.serverId,
              status: prev == null ? PollStatus.baseline : PollStatus.updated,
            ),
            diffSnapshots(prev, snapshot),
          );
      }
    } on Object {
      return (_failed(t, ErrorCategory.parseError), <ChangeEvent>[]);
    }
  }

  PollOutcome _failed(PollTarget t, ErrorCategory c) =>
      PollOutcome(serverId: t.serverId, status: PollStatus.failed, error: c);
}
