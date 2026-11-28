// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart' show ParseRunner;
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/domain/server_models.dart'
    show ServerCredentials;
import 'package:core/core.dart' show Result;

/// Per-connection memory for a source (a torrent client keeps its session in
/// it). Closed when the connection changes or the dashboard goes away.
class SourceSession {
  final Map<String, Object> _values = {};
  final List<void Function()> _closers = [];

  bool has(String key) => _values.containsKey(key);

  /// The value stored under [key], created (once) with [create].
  T of<T extends Object>(
    String key,
    T Function() create, {
    void Function(T value)? close,
  }) {
    final existing = _values[key];
    if (existing != null) return existing as T;
    final value = create();
    _values[key] = value;
    if (close != null) _closers.add(() => close(value));
    return value;
  }

  void close() {
    for (final closer in _closers) {
      closer();
    }
    _closers.clear();
    _values.clear();
  }
}

/// What a source gets for one request group.
class SourceContext {
  const SourceContext({
    required this.connection,
    required this.loadCredentials,
    required this.session,
    required this.now,
    required this.utcOffset,
    required this.onRowsSkipped,
    this.runner,
  });

  final ServerConnection connection;

  /// Reads the stored credentials (clients that log in themselves).
  final Future<ServerCredentials> Function() loadCredentials;
  final SourceSession session;

  /// The current time and the zone's offset from UTC.
  final DateTime now;
  final Duration utcOffset;

  /// Reports the number (only) of malformed rows a client skipped.
  final void Function(int skipped) onRowsSkipped;

  /// Replaces the isolate runner (tests).
  final ParseRunner? runner;
}

typedef ActivityFetch = Future<Result<ActivitySummary>> Function(
  SourceContext context,
);
typedef MediaFetch = Future<Result<List<MediaItem>>> Function(
  SourceContext context,
);

/// What one service kind can put on the dashboard. A card the kind does not
/// feed is `null`.
class DashboardSource {
  const DashboardSource({this.activity, this.upcoming, this.recent});

  final ActivityFetch? activity;
  final MediaFetch? upcoming;
  final MediaFetch? recent;

  bool feeds(DashboardCard card) => switch (card) {
    DashboardCard.activity => activity != null,
    DashboardCard.upcoming => upcoming != null,
    DashboardCard.recent => recent != null,
  };
}
