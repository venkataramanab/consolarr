// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:torrent_clients/torrent_clients.dart';

/// The status tabs of the torrent list (TOR-01).
enum TorrentTab { all, active, downloading, finished, error }

/// What the list is ordered by.
enum TorrentSort {
  name,
  status,
  progress,
  size,
  added,
  ratio,
  label,
  downSpeed,
  upSpeed,
  timeLeft,
}

/// Tab, order and search of the list. [query] is never persisted.
class TorrentView {
  const TorrentView({
    this.tab = TorrentTab.all,
    this.sort = TorrentSort.added,
    this.ascending = false,
    this.query = '',
  });

  final TorrentTab tab;
  final TorrentSort sort;
  final bool ascending;
  final String query;

  bool get isFiltered => tab != TorrentTab.all || query.trim().isNotEmpty;

  TorrentView copyWith({
    TorrentTab? tab,
    TorrentSort? sort,
    bool? ascending,
    String? query,
  }) => TorrentView(
    tab: tab ?? this.tab,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    query: query ?? this.query,
  );

  @override
  bool operator ==(Object other) =>
      other is TorrentView &&
      other.tab == tab &&
      other.sort == sort &&
      other.ascending == ascending &&
      other.query == query;

  @override
  int get hashCode => Object.hash(tab, sort, ascending, query);
}

bool _active(Torrent t) =>
    t.state == TorrentState.downloading ||
    t.state == TorrentState.seeding && t.upSpeed > 0 ||
    t.dlSpeed > 0 ||
    t.upSpeed > 0;

/// Whether [t] belongs on [tab].
bool matchesTab(Torrent t, TorrentTab tab) => switch (tab) {
  TorrentTab.all => true,
  TorrentTab.active => _active(t),
  TorrentTab.downloading =>
    t.state == TorrentState.downloading ||
        t.state == TorrentState.stalled ||
        t.state == TorrentState.queued && t.progress < 1,
  TorrentTab.finished =>
    t.state == TorrentState.finished ||
        t.state == TorrentState.seeding ||
        t.progress >= 1 && t.state != TorrentState.error,
  TorrentTab.error => t.state == TorrentState.error,
};

int _compare(Torrent a, Torrent b, TorrentSort sort) {
  switch (sort) {
    case TorrentSort.name:
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    case TorrentSort.status:
      return a.state.index.compareTo(b.state.index);
    case TorrentSort.progress:
      return a.progress.compareTo(b.progress);
    case TorrentSort.size:
      return a.size.compareTo(b.size);
    case TorrentSort.added:
      final x = a.addedOn?.millisecondsSinceEpoch ?? 0;
      final y = b.addedOn?.millisecondsSinceEpoch ?? 0;
      return x.compareTo(y);
    case TorrentSort.ratio:
      return _ratioKey(a).compareTo(_ratioKey(b));
    case TorrentSort.label:
      return (a.category ?? a.label ?? '').toLowerCase().compareTo(
        (b.category ?? b.label ?? '').toLowerCase(),
      );
    case TorrentSort.downSpeed:
      return a.dlSpeed.compareTo(b.dlSpeed);
    case TorrentSort.upSpeed:
      return a.upSpeed.compareTo(b.upSpeed);
    case TorrentSort.timeLeft:
      // An unknown time left sorts as "longest".
      final x = a.eta?.inSeconds ?? 1 << 40;
      final y = b.eta?.inSeconds ?? 1 << 40;
      return x.compareTo(y);
  }
}

/// The torrents of [all] that match the tab and search of [view], in its
/// order (ties keep the name order so the list does not jump).
List<Torrent> applyView(List<Torrent> all, TorrentView view) {
  final q = view.query.trim().toLowerCase();
  final out = [
    for (final t in all)
      if (matchesTab(t, view.tab) &&
          (q.isEmpty || t.name.toLowerCase().contains(q)))
        t,
  ];
  out.sort((a, b) {
    final c = _compare(a, b, view.sort);
    final ordered = view.ascending ? c : -c;
    return ordered != 0 ? ordered : a.name.compareTo(b.name);
  });
  return out;
}

/// Sort key of a ratio: unknown (`-1`) first, infinite (`-2`) last.
double _ratioKey(Torrent t) => t.ratioInfinite
    ? double.infinity
    : t.ratioUnknown
    ? -1
    : t.ratio;
