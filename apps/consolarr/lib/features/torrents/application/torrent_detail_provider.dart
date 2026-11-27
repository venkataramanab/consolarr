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

  /// Bumped by every build (a client switch rebuilds), so a refresh started
  /// for an earlier build can be recognised and dropped.
  int _generation = 0;

  @override
  Future<TorrentDetail> build() async {
    _generation++;
    final client = await ref.watch(torrentClientProvider.future);
    if (client == null) throw const AppError(ErrorCategory.notFound);
    return (await client.torrentDetail(hash))
        .when(ok: (d) => d, err: (e) => throw e);
  }

  /// Silent refresh: no loading state, failures keep the old data. Returns
  /// `false` when the read failed (the poller backs off). A result for a
  /// client that was replaced meanwhile, or after a rebuild, is dropped.
  Future<bool> refresh() async {
    if (state.isLoading || state.hasError) return true;
    final generation = _generation;
    // Captured before the await: `ref.read`, never `watch`, outside build.
    final client = ref.read(torrentClientProvider).value;
    if (client == null) return true;
    final result = await client.torrentDetail(hash);
    if (!ref.mounted ||
        generation != _generation ||
        !identical(client, ref.read(torrentClientProvider).value)) {
      return true;
    }
    return result.when(
      ok: (d) {
        state = AsyncData(d);
        return true;
      },
      err: (_) => false,
    );
  }
}
