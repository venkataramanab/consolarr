// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/polling/change_detection/change_detection.dart';
import 'package:consolarr/shared/polling/poll_telemetry.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';

class _Sink implements Analytics {
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async => events.add((name, parameters));
}

void main() {
  test('cycle and change events carry counts and enums only', () async {
    final sink = _Sink();
    final cycle = trackedPollCycle(
      EventTracker(analytics: sink, breadcrumbs: Breadcrumbs()),
    );
    var state = TrackedState.active;
    final target = PollTarget(
      serverId: 'srv-secret-id',
      kind: ServiceKind.sonarr,
      source: () async => Result.ok(
        SnapshotFetch([
          TrackedItem(
            key: 'arr:7',
            source: TrackedSource.arrQueue,
            state: state,
            title: 'Secret Title',
          ),
        ]),
      ),
    );
    await cycle.run([target]);
    state = TrackedState.completed;
    await cycle.run([target]);
    await Future<void>.delayed(Duration.zero);

    expect(sink.events.map((e) => e.$1), [
      'poll_cycle_finished',
      'poll_change_detected',
      'poll_cycle_finished',
    ]);
    expect(sink.events[1].$2, {'change': 'queue_item_completed'});
    expect(sink.events.last.$2, {'servers': 1, 'failed': 0, 'changes': 1});
    final all = sink.events.toString();
    expect(all, isNot(contains('Secret')));
    expect(all, isNot(contains('srv-')));
    expect(all, isNot(contains('arr:7')));
  });

  test('every change type maps to a distinct event value', () {
    expect(
      {for (final t in ChangeType.values) pollChangeParam(t)}.length,
      ChangeType.values.length,
    );
  });
}
