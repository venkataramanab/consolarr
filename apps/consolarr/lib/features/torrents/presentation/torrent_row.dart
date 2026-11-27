// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:consolarr/features/torrents/presentation/torrent_state_view.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// One torrent as a progress-fill row (TOR-02). The name is plain text from
/// the server; state is icon + text; the spoken label has state and percent.
class TorrentRow extends StatelessWidget {
  const TorrentRow({required this.torrent, super.key});

  final Torrent torrent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final view = torrentStateView(l10n, torrent.state);
    final percent = l10n.torProgressPercent(torrent.progress);
    final active = torrent.state == TorrentState.downloading;
    return ProgressFillRow(
      title: torrent.name,
      progress: torrent.progress,
      state: view.rowState,
      stateIcon: view.icon,
      stateLabel: view.label,
      progressLabel: percent,
      semanticsLabel: l10n.torRowSemantics(torrent.name, view.label, percent),
      details: [
        l10n.torDetailSize(formatBytes(l10n, torrent.size)),
        if (torrent.dlSpeed > 0)
          l10n.torDetailDown(formatSpeed(l10n, torrent.dlSpeed)),
        if (torrent.upSpeed > 0)
          l10n.torDetailUp(formatSpeed(l10n, torrent.upSpeed)),
        if (active && torrent.eta != null)
          l10n.torDetailEta(formatDuration(l10n, torrent.eta!)),
        l10n.torDetailRatio(torrent.ratio),
      ],
    );
  }
}
