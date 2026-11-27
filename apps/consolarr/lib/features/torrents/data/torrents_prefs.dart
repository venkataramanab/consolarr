// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrent_view.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:core/core.dart';

/// Small torrent preferences in the key/value `AppStateRows` table. Values
/// are closed enums and integers; never a link, name or path. Every read
/// tolerates a missing or damaged value.
class TorrentsPrefs {
  TorrentsPrefs(this._db);

  final AppDatabase _db;

  static const selectedKindKey = 'torrents.selected_kind';
  static const pollSecondsKey = 'torrents.poll_seconds';
  static const viewDefaultKey = 'torrents.view_default';
  static String delugeHostKey(String serverId) =>
      'torrents.deluge_host.$serverId';

  Future<String?> _read(String key) async {
    try {
      final row = await (_db.select(
        _db.appStateRows,
      )..where((r) => r.key.equals(key))).getSingleOrNull();
      return row?.value;
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, String value) => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(key: key, value: value),
      );

  /// The kind chosen in the server switcher, live.
  Stream<ServiceKind?> watchSelectedKind() =>
      (_db.select(_db.appStateRows)
            ..where((r) => r.key.equals(selectedKindKey)))
          .watchSingleOrNull()
          .map((row) => _kind(row?.value));

  static ServiceKind? _kind(String? name) {
    for (final k in ServiceKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  Future<int?> readPollSeconds() async {
    final v = int.tryParse(await _read(pollSecondsKey) ?? '');
    return v != null && v >= 1 && v <= 300 ? v : null;
  }

  Future<void> writePollSeconds(int seconds) =>
      _write(pollSecondsKey, '$seconds');

  /// The saved default tab and order (never the search text).
  Future<TorrentView?> readViewDefault() async {
    final parts = (await _read(viewDefaultKey))?.split(',');
    if (parts == null || parts.length != 3) return null;
    TorrentTab? tab;
    for (final t in TorrentTab.values) {
      if (t.name == parts[0]) tab = t;
    }
    TorrentSort? sort;
    for (final s in TorrentSort.values) {
      if (s.name == parts[1]) sort = s;
    }
    if (tab == null || sort == null) return null;
    return TorrentView(tab: tab, sort: sort, ascending: parts[2] == 'asc');
  }

  Future<void> writeViewDefault(TorrentView view) => _write(
    viewDefaultKey,
    '${view.tab.name},${view.sort.name},${view.ascending ? 'asc' : 'desc'}',
  );

  Future<String?> readDelugeHost(String serverId) =>
      _read(delugeHostKey(serverId));

  Future<void> writeDelugeHost(String serverId, String hostId) =>
      _write(delugeHostKey(serverId), hostId);
}
