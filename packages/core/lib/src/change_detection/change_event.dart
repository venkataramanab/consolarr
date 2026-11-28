// SPDX-License-Identifier: GPL-3.0-or-later

/// What happened. Maps one to one onto the `poll_change_param` event enum.
enum ChangeType { queueItemCompleted, downloadFailed, torrentFinished }

/// A detected change. [title] is for a future notification only: it is held in
/// memory, excluded from [toString] and [toJson], and never persisted or
/// logged.
class ChangeEvent {
  const ChangeEvent({
    required this.type,
    required this.serverId,
    required this.itemKey,
    this.title,
  });

  final ChangeType type;
  final String serverId;
  final String itemKey;
  final String? title;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'serverId': serverId,
    'itemKey': itemKey,
  };

  @override
  String toString() => 'ChangeEvent(${type.name})';
}
