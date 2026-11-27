// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrent_actions_controller.dart';
import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:consolarr/features/torrents/presentation/torrent_state_view.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// One torrent as a progress-fill row (TOR-02). The name is plain text from
/// the server; state is icon + text; the spoken label has state and percent.
///
/// The list reuses the same widget instance while a row's own data
/// ([torrent], [pending]) is unchanged, so only changed rows rebuild.
class TorrentRow extends StatelessWidget {
  const TorrentRow({
    required this.torrent,
    this.pending,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final Torrent torrent;
  final PendingAction? pending;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Counts builds (the rebuild-bound test reads it).
  @visibleForTesting
  static int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final l10n = context.l10n;
    final view = torrentStateView(l10n, torrent.state);
    final percent = l10n.torProgressPercent(torrent.progress);
    final active = torrent.state == TorrentState.downloading;
    final stateLabel = switch (pending) {
      PendingAction.pausing => l10n.torPendingPausing,
      PendingAction.resuming => l10n.torPendingResuming,
      PendingAction.removing => l10n.torPendingRemoving,
      null => view.label,
    };
    final size = l10n.torDetailSize(formatBytes(l10n, torrent.size));
    final down = torrent.dlSpeed > 0
        ? l10n.torDetailDown(formatSpeed(l10n, torrent.dlSpeed))
        : null;
    final up = torrent.upSpeed > 0
        ? l10n.torDetailUp(formatSpeed(l10n, torrent.upSpeed))
        : null;
    final eta = active && torrent.eta != null
        ? l10n.torDetailEta(formatDuration(l10n, torrent.eta!))
        : null;
    final details = [size, ?down, ?up, ?eta, ratioDetail(l10n, torrent)];
    // The spoken label carries what the eye sees: speeds and time left too.
    final spokenDetails = [
      size,
      ?down,
      ?up,
      ?eta,
      if (torrent.ratioUnknown || torrent.ratioInfinite)
        l10n.torDetailRatioValue(ratioSpoken(l10n, torrent))
      else
        ratioDetail(l10n, torrent),
    ].join(l10n.torListSeparator);
    return ProgressFillRow(
      title: torrent.name,
      progress: torrent.progress,
      state: view.rowState,
      stateIcon: pending == null ? view.icon : Icons.hourglass_empty,
      stateLabel: stateLabel,
      progressLabel: percent,
      semanticsLabel: l10n.torRowSemantics(
        torrent.name,
        stateLabel,
        percent,
        spokenDetails,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
      details: details,
    );
  }
}
