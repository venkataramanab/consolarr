// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// One torrent in detail (TOR-08), loaded when the sheet opens and refreshed
/// by the sheet while it is open (and only then: the provider is auto
/// disposed with it). A failed refresh keeps the last data.
final torrentDetailProvider = AsyncNotifierProvider.autoDispose
    .family<TorrentDetailNotifier, TorrentDetail, String>(
      TorrentDetailNotifier.new,
      retry: (_, _) => null,
    );

class TorrentDetailNotifier extends AsyncNotifier<TorrentDetail> {
  TorrentDetailNotifier(this.hash);

  final String hash;

  Future<Result<TorrentDetail>> _load() async {
    final client = await ref.watch(torrentClientProvider.future);
    if (client == null)
      return const Result.err(AppError(ErrorCategory.notFound));
    return client.torrentDetail(hash);
  }

  @override
  Future<TorrentDetail> build() async =>
      (await _load()).when(ok: (d) => d, err: (e) => throw e);

  /// Silent refresh: no loading state, failures keep the old data.
  Future<void> refresh() async {
    if (state.isLoading || state.hasError) return;
    final r = await _load();
    if (!ref.mounted) return;
    r.when(ok: (d) => state = AsyncData(d), err: (_) {});
  }
}
