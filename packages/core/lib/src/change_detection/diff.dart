// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/polling/change_detection/change_event.dart';
import 'package:consolarr/shared/polling/change_detection/tracked_item.dart';

/// The events between two snapshots of the same server (pure).
///
/// * A null [prev] is the baseline: nothing is emitted.
/// * Only an observed transition counts: the item was present and not yet
///   terminal in [prev] and is completed or failed in [next]. A new item, an
///   item that was already terminal and an item that disappeared (removed by
///   hand) emit nothing.
List<ChangeEvent> diffSnapshots(ServiceSnapshot? prev, ServiceSnapshot next) {
  if (prev == null) return const [];
  final events = <ChangeEvent>[];
  for (final item in next.items.values) {
    final before = prev.items[item.key];
    if (before == null || before.isTerminal) continue;
    final type = switch (item.state) {
      TrackedState.failed => ChangeType.downloadFailed,
      TrackedState.completed =>
        item.source == TrackedSource.torrent
            ? ChangeType.torrentFinished
            : ChangeType.queueItemCompleted,
      _ => null,
    };
    if (type == null) continue;
    events.add(
      ChangeEvent(
        type: type,
        serverId: next.serverId,
        itemKey: item.key,
        title: item.title,
      ),
    );
  }
  return events;
}
