// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/polling/change_detection/change_detection.dart';
import 'package:observability/observability.dart';

/// The `poll_*` event for a change type (closed enum, one to one).
PollChangeParam pollChangeParam(ChangeType type) => switch (type) {
  ChangeType.queueItemCompleted => PollChangeParam.queueItemCompleted,
  ChangeType.downloadFailed => PollChangeParam.downloadFailed,
  ChangeType.torrentFinished => PollChangeParam.torrentFinished,
};

/// A [PollCycle] reporting counts and change kinds only: no title, id, host or
/// server reference can reach an event.
PollCycle trackedPollCycle(EventTracker tracker, {ChangeLedger? ledger}) =>
    PollCycle(
      ledger: ledger,
      onCycleFinished: (servers, failed, changes) => tracker.track(
        PollCycleFinishedEvent(
          servers: countBucket(servers),
          failed: countBucket(failed),
          changes: countBucket(changes),
        ),
      ),
      onChange: (type) =>
          tracker.track(PollChangeDetectedEvent(change: pollChangeParam(type))),
    );
