// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrent_view.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Tab, order and search of the list. The saved default (tab and order) is
/// applied once it has been read; the search text is never saved.
final torrentViewProvider = NotifierProvider<TorrentViewNotifier, TorrentView>(
  TorrentViewNotifier.new,
);

class TorrentViewNotifier extends Notifier<TorrentView> {
  bool _touched = false;

  @override
  TorrentView build() {
    unawaited(_loadDefault());
    return const TorrentView();
  }

  Future<void> _loadDefault() async {
    final saved = await ref.read(torrentsPrefsProvider).readViewDefault();
    // A choice made before the read finished wins.
    if (saved == null || _touched || !ref.mounted) return;
    state = saved.copyWith(query: state.query);
  }

  void setTab(TorrentTab tab) {
    _touched = true;
    state = state.copyWith(tab: tab);
  }

  void setQuery(String query) => state = state.copyWith(query: query);

  /// Applies the sort sheet; with [saveAsDefault] the tab and order are
  /// remembered for the next start.
  Future<void> applySort(
    TorrentSort sort, {
    required bool ascending,
    required bool saveAsDefault,
  }) async {
    _touched = true;
    state = state.copyWith(sort: sort, ascending: ascending);
    if (saveAsDefault) {
      try {
        await ref.read(torrentsPrefsProvider).writeViewDefault(state);
      } on Object {
        // Applies for this session even when it cannot be saved.
      }
    }
  }

  void clearFilters() => state = state.copyWith(tab: TorrentTab.all, query: '');
}

/// The torrents the list shows: the loaded list with the view applied. Empty
/// while the list is loading, failed or without a server.
final visibleTorrentsProvider = Provider<List<Torrent>>((ref) {
  final async = ref.watch(torrentListProvider);
  if (async.isLoading || async.hasError) return const [];
  final value = async.value;
  if (value is! TorrentsData) return const [];
  return applyView(value.torrents, ref.watch(torrentViewProvider));
});
