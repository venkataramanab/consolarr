// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/json_read.dart';

/// Lifecycle of a server command (`/command/{id}`).
enum ArrCommandStatus {
  queued,
  started,
  completed,
  failed,
  aborted,
  cancelled,
  orphaned,
  unknown,
}

/// A server-side command (search, refresh, ...). Only the fields the app
/// needs; the name and message are plain text and never logged with titles.
class ArrCommand {
  const ArrCommand({
    required this.id,
    required this.status,
    this.name,
    this.message,
  });

  factory ArrCommand.fromJson(Map<String, Object?> json) => ArrCommand(
    id: JsonRead.requiredInt(json, 'id'),
    name: JsonRead.string(json, 'name'),
    message: JsonRead.string(json, 'message'),
    status: ArrCommandStatus.values.firstWhere(
      (s) => s.name == JsonRead.string(json, 'status')?.toLowerCase(),
      orElse: () => ArrCommandStatus.unknown,
    ),
  );

  final int id;
  final String? name;
  final String? message;
  final ArrCommandStatus status;

  /// No further status changes will happen.
  bool get isTerminal => switch (status) {
    ArrCommandStatus.queued ||
    ArrCommandStatus.started ||
    ArrCommandStatus.unknown => false,
    _ => true,
  };

  bool get isSuccess => status == ArrCommandStatus.completed;

  @override
  bool operator ==(Object other) =>
      other is ArrCommand &&
      other.id == id &&
      other.status == status &&
      other.name == name &&
      other.message == message;

  @override
  int get hashCode => Object.hash(id, status, name, message);

  /// No name or message: they can carry titles.
  @override
  String toString() => 'ArrCommand($id, ${status.name})';
}

/// A command to start: the `name` plus its flat parameters.
class ArrCommandRequest {
  const ArrCommandRequest(this.name, [this.params = const {}]);

  final String name;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => {'name': name, ...params};
}
