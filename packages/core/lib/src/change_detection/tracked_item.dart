// SPDX-License-Identifier: GPL-3.0-or-later

/// Where a tracked item comes from.
enum TrackedSource { arrQueue, torrent }

/// A download reduced to what change detection needs.
enum TrackedState { active, completed, failed, other }

/// One download of one server. [key] is stable per server (a queue id or a
/// torrent hash); [title] is server text kept in memory only for a future
/// notification: it is excluded from [toString] and never persisted.
class TrackedItem {
  const TrackedItem({
    required this.key,
    required this.source,
    required this.state,
    this.progress = 0,
    this.title,
  });

  final String key;
  final TrackedSource source;
  final TrackedState state;

  /// 0..1.
  final double progress;
  final String? title;

  bool get isTerminal =>
      state == TrackedState.completed || state == TrackedState.failed;

  @override
  String toString() => 'TrackedItem(${source.name}, ${state.name})';
}

/// All tracked items of one server at one point in time.
class ServiceSnapshot {
  ServiceSnapshot({
    required this.serverId,
    required Iterable<TrackedItem> items,
  }) : items = {for (final i in items) i.key: i};

  final String serverId;
  final Map<String, TrackedItem> items;

  @override
  String toString() => 'ServiceSnapshot(${items.length} items)';
}
