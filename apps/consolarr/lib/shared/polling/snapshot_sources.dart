// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/shared/polling/change_detection/change_detection.dart';
import 'package:core/core.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// The clients a source can be built from. A kind uses the one it needs.
class SnapshotClients {
  const SnapshotClients({this.sonarr, this.radarr, this.torrent});

  final SonarrApi? sonarr;
  final RadarrApi? radarr;
  final TorrentClient? torrent;
}

typedef SnapshotSourceBuilder = SnapshotSource Function(SnapshotClients c);

/// Snapshot sources per [ServiceKind]: one line per kind, no switches. The
/// existing shared lists are used; no new endpoint is called.
///
/// Wiring to real servers (`activeConnectionProvider(kind)` -> client ->
/// [PollTarget]) is documented in `docs/patterns.md` and deliberately not
/// shipped: nothing polls in the background.
final Map<ServiceKind, SnapshotSourceBuilder> snapshotSources = {
  ServiceKind.sonarr: (c) => arrQueueSource(c.sonarr!.queue),
  ServiceKind.radarr: (c) => arrQueueSource(c.radarr!.queue),
  ServiceKind.qbittorrent: (c) => torrentSource(c.torrent!),
  ServiceKind.transmission: (c) => torrentSource(c.torrent!),
  ServiceKind.deluge: (c) => torrentSource(c.torrent!),
};

/// Queue states that mean the download is done (waiting for or doing the
/// import) are completed; import and download failures are failed.
TrackedState trackedStateOfQueue(ArrQueueState s) => switch (s) {
  ArrQueueState.downloading ||
  ArrQueueState.paused ||
  ArrQueueState.queued ||
  ArrQueueState.delayed => TrackedState.active,
  ArrQueueState.importPending ||
  ArrQueueState.importing ||
  ArrQueueState.completed => TrackedState.completed,
  ArrQueueState.importFailed ||
  ArrQueueState.downloadFailed => TrackedState.failed,
  ArrQueueState.clientUnavailable ||
  ArrQueueState.warning ||
  ArrQueueState.ignored ||
  ArrQueueState.unknown => TrackedState.other,
};

TrackedState trackedStateOfTorrent(TorrentState s) => switch (s) {
  TorrentState.downloading ||
  TorrentState.stalled ||
  TorrentState.checking ||
  TorrentState.queued ||
  TorrentState.paused => TrackedState.active,
  TorrentState.seeding || TorrentState.finished => TrackedState.completed,
  TorrentState.error => TrackedState.failed,
  TorrentState.unknown => TrackedState.other,
};

/// A source over the queue of a Sonarr or Radarr server. Keys are queue ids,
/// never titles. [skippedRows] is the running count of malformed rows the
/// client reported; a fetch during which it grew is partial.
SnapshotSource arrQueueSource(
  Future<Result<List<ArrQueueItem>>> Function() queue, {
  int Function()? skippedRows,
}) {
  var seen = skippedRows?.call() ?? 0;
  return () async {
    final result = await queue();
    final now = skippedRows?.call() ?? 0;
    final partial = now != seen;
    seen = now;
    return result.map(
      (items) => SnapshotFetch([
        for (final i in items)
          TrackedItem(
            key: 'arr:${i.id}',
            source: TrackedSource.arrQueue,
            state: trackedStateOfQueue(i.state),
            progress: i.size > 0 ? 1 - i.sizeLeft / i.size : 0.0,
            title: i.mediaTitle ?? i.title,
          ),
      ], partial: partial),
    );
  };
}

/// A source over a torrent client's list. Keys are hashes.
SnapshotSource torrentSource(
  TorrentClient client, {
  int Function()? skippedRows,
}) {
  var seen = skippedRows?.call() ?? 0;
  return () async {
    final result = await client.listTorrents();
    final now = skippedRows?.call() ?? 0;
    final partial = now != seen;
    seen = now;
    return result.map(
      (torrents) => SnapshotFetch([
        for (final t in torrents)
          TrackedItem(
            key: 'tor:${t.hash}',
            source: TrackedSource.torrent,
            state: trackedStateOfTorrent(t.state),
            progress: t.progress,
            title: t.name,
          ),
      ], partial: partial),
    );
  };
}
