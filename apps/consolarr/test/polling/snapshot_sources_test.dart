// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/shared/polling/change_detection/change_detection.dart';
import 'package:consolarr/shared/polling/snapshot_sources.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart';

class _Arr implements SonarrApi {
  _Arr(this.items);
  List<ArrQueueItem> items;

  @override
  ServiceKind get kind => ServiceKind.sonarr;

  @override
  Future<Result<List<ArrQueueItem>>> queue() async => Result.ok(items);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Tor implements TorrentClient {
  _Tor(this.torrents);
  List<Torrent> torrents;

  @override
  ServiceKind get kind => ServiceKind.qbittorrent;

  @override
  Future<Result<List<Torrent>>> listTorrents() async => Result.ok(torrents);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ArrQueueItem q(int id, ArrQueueState s) => ArrQueueItem(
  id: id,
  title: 'Release $id',
  state: s,
  mediaTitle: 'Show $id',
);

Torrent t(String hash, TorrentState s) => Torrent(
  hash: hash,
  name: 'name $hash',
  state: s,
  progress: s == TorrentState.seeding ? 1 : 0.2,
  size: 10,
  dlSpeed: 0,
  upSpeed: 0,
  ratio: 0,
);

void main() {
  test('queue states map to tracked states', () {
    const expected = {
      ArrQueueState.downloading: TrackedState.active,
      ArrQueueState.paused: TrackedState.active,
      ArrQueueState.queued: TrackedState.active,
      ArrQueueState.delayed: TrackedState.active,
      ArrQueueState.importPending: TrackedState.completed,
      ArrQueueState.importing: TrackedState.completed,
      ArrQueueState.completed: TrackedState.completed,
      ArrQueueState.importFailed: TrackedState.failed,
      ArrQueueState.downloadFailed: TrackedState.failed,
      ArrQueueState.warning: TrackedState.other,
      ArrQueueState.clientUnavailable: TrackedState.other,
      ArrQueueState.ignored: TrackedState.other,
      ArrQueueState.unknown: TrackedState.other,
    };
    expect(expected.keys.toSet(), ArrQueueState.values.toSet());
    for (final e in expected.entries) {
      expect(trackedStateOfQueue(e.key), e.value, reason: '${e.key}');
    }
  });

  test('torrent states map to tracked states', () {
    expect(trackedStateOfTorrent(TorrentState.seeding), TrackedState.completed);
    expect(
      trackedStateOfTorrent(TorrentState.finished),
      TrackedState.completed,
    );
    expect(trackedStateOfTorrent(TorrentState.error), TrackedState.failed);
    expect(trackedStateOfTorrent(TorrentState.unknown), TrackedState.other);
    for (final s in [
      TorrentState.downloading,
      TorrentState.stalled,
      TorrentState.checking,
      TorrentState.queued,
      TorrentState.paused,
    ]) {
      expect(trackedStateOfTorrent(s), TrackedState.active, reason: '$s');
    }
  });

  test('registry has one entry per service kind', () {
    expect(snapshotSources.keys.toSet(), ServiceKind.values.toSet());
  });

  test('arr queue source fetches items without logging titles', () async {
    final api = _Arr([q(1, ArrQueueState.downloading)]);
    final r = await snapshotSources[ServiceKind.sonarr]!(
      SnapshotClients(sonarr: api),
    )();
    final fetch = (r as Ok<SnapshotFetch>).value;
    expect(fetch.items.single.key, 'arr:1');
    expect(fetch.items.single.source, TrackedSource.arrQueue);
    expect(fetch.items.single.title, 'Show 1');
    expect(fetch.partial, isFalse);
  });

  test('skipped rows make the fetch partial', () async {
    var skipped = 0;
    final source = arrQueueSource(
      _Arr([q(1, ArrQueueState.downloading)]).queue,
      skippedRows: () => skipped,
    );
    expect(((await source()) as Ok<SnapshotFetch>).value.partial, isFalse);
    skipped = 2;
    expect(((await source()) as Ok<SnapshotFetch>).value.partial, isTrue);
    // The counter is read per fetch: the same count again is not "new".
    expect(((await source()) as Ok<SnapshotFetch>).value.partial, isFalse);
  });

  test('torrent source and a full cycle: seeding after downloading', () async {
    final client = _Tor([t('h1', TorrentState.downloading)]);
    final cycle = PollCycle();
    final target = PollTarget(
      serverId: 'tor',
      kind: ServiceKind.qbittorrent,
      source: snapshotSources[ServiceKind.qbittorrent]!(
        SnapshotClients(torrent: client),
      ),
    );
    await cycle.run([target]);
    client.torrents = [t('h1', TorrentState.seeding)];
    final r = await cycle.run([target]);
    expect(r.events.single.type, ChangeType.torrentFinished);
    expect(r.events.single.itemKey, 'tor:h1');
  });

  test('a client error is passed through as an error result', () async {
    final failing = _Failing();
    final r = await arrQueueSource(failing.queue)();
    expect(r.isErr, isTrue);
  });
}

class _Failing extends _Arr {
  _Failing() : super([]);
  @override
  Future<Result<List<ArrQueueItem>>> queue() async =>
      const Result.err(AppError(ErrorCategory.timeout));
}
