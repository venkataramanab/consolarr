// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:consolarr/features/torrents/torrents_routes.dart'
    show torrentsRoute;
import 'package:core/core.dart';
import 'package:torrent_clients/torrent_clients.dart'
    show DelugeHostRequired, Torrent, TorrentClient, TorrentState, TransferInfo;

const _torrentsTab = DashboardLink(
  torrentsRoute,
  DashboardTarget.tab,
  DashboardDestination.torrents,
);

/// The activity of a torrent client of [kind]. The client comes from the
/// torrents feature's factory registry, with no remembered Deluge host and no
/// callbacks that write; its session lives in the [SourceSession] and is
/// forgotten with it.
DashboardSource torrentDashboardSource(ServiceKind kind) => DashboardSource(
  activity: (c) async {
    final factory = torrentClientFactories[kind];
    if (factory == null) {
      return const Result.err(AppError(ErrorCategory.notFound));
    }
    // Stored credentials are read once per connection, not on every poll.
    final credentials = c.session.has('torrent')
        ? null
        : await c.loadCredentials();
    final client = c.session.of<TorrentClient>(
      'torrent',
      () => factory(
        TorrentClientContext(
          dio: c.dio,
          profile: c.connection.profile,
          credentials: credentials!,
          onRowsSkipped: c.onRowsSkipped,
        ),
      ),
      close: (client) => client.forgetSession(),
    );
    // Both requests go out together; the statistics are optional.
    final listFuture = client.listTorrents();
    final transferFuture = client.transferInfo();
    final list = await listFuture;
    final error = list.errorOrNull;
    if (error != null) {
      // The Deluge host list holds addresses: keep only the category and the
      // marker the card needs.
      // The statistics request is not needed any more.
      unawaited(transferFuture.then<void>((_) {}, onError: (_) {}));
      return Result.err(
        error is DelugeHostRequired ? const HostChoiceRequired() : error,
      );
    }
    final transfer = await transferFuture;
    return Result.ok(
      summarizeTorrents(list.valueOrNull!, transfer.valueOrNull),
    );
  },
);

ActivityState _state(TorrentState s) => switch (s) {
  TorrentState.downloading => ActivityState.downloading,
  TorrentState.stalled => ActivityState.stalled,
  TorrentState.checking => ActivityState.checking,
  TorrentState.queued => ActivityState.queued,
  TorrentState.seeding => ActivityState.seeding,
  TorrentState.paused => ActivityState.paused,
  TorrentState.finished => ActivityState.completed,
  TorrentState.error => ActivityState.attention,
  TorrentState.unknown => ActivityState.queued,
};

/// Counts over every torrent; keeps the [kActivityRows] most relevant rows
/// (errors first, then the downloads closest to done) in one pass, so 10,000
/// torrents cost no sort.
ActivitySummary summarizeTorrents(
  List<Torrent> torrents,
  TransferInfo? transfer,
) {
  var active = 0;
  var attention = 0;
  final top = <Torrent>[];
  int rank(Torrent t) => t.state == TorrentState.error ? 0 : 1;
  bool better(Torrent a, Torrent b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r < 0 : a.progress > b.progress;
  }

  for (final t in torrents) {
    final isError = t.state == TorrentState.error;
    final isShown =
        isError ||
        t.state == TorrentState.downloading ||
        t.state == TorrentState.stalled ||
        t.state == TorrentState.checking;
    if (isError) attention++;
    if (t.state == TorrentState.downloading) active++;
    if (!isShown) continue;
    if (top.length < kActivityRows) {
      top.add(t);
    } else {
      var worst = 0;
      for (var i = 1; i < top.length; i++) {
        if (better(top[worst], top[i])) worst = i;
      }
      if (better(t, top[worst])) top[worst] = t;
    }
  }
  top.sort((a, b) => better(a, b) ? -1 : (better(b, a) ? 1 : 0));
  return ActivitySummary(
    active: active,
    attention: attention,
    link: _torrentsTab,
    downSpeed: transfer?.dlSpeed,
    upSpeed: transfer?.upSpeed,
    speedUnavailable: transfer == null,
    rows: [
      for (final t in top)
        ActivityRow(
          id: t.hash,
          title: t.name,
          state: _state(t.state),
          progress: t.progress,
          sizeLeft: t.size > 0 ? ((1 - t.progress) * t.size).round() : null,
          eta: t.eta,
          speed: t.dlSpeed,
        ),
    ],
  );
}
