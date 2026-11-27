// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// How one [TorrentState] looks: icon and text always, plus the row emphasis.
class TorrentStateView {
  const TorrentStateView({
    required this.rowState,
    required this.icon,
    required this.label,
  });

  final ProgressRowState rowState;
  final IconData icon;
  final String label;
}

TorrentStateView torrentStateView(AppLocalizations l10n, TorrentState state) =>
    switch (state) {
      TorrentState.downloading => TorrentStateView(
        rowState: ProgressRowState.active,
        icon: Icons.arrow_downward,
        label: l10n.torStateDownloading,
      ),
      TorrentState.stalled => TorrentStateView(
        rowState: ProgressRowState.queued,
        icon: Icons.swap_vert,
        label: l10n.torStateStalled,
      ),
      TorrentState.checking => TorrentStateView(
        rowState: ProgressRowState.active,
        icon: Icons.fact_check_outlined,
        label: l10n.torStateChecking,
      ),
      TorrentState.queued => TorrentStateView(
        rowState: ProgressRowState.queued,
        icon: Icons.schedule,
        label: l10n.torStateQueued,
      ),
      TorrentState.seeding => TorrentStateView(
        rowState: ProgressRowState.idle,
        icon: Icons.arrow_upward,
        label: l10n.torStateSeeding,
      ),
      TorrentState.paused => TorrentStateView(
        rowState: ProgressRowState.paused,
        icon: Icons.pause_circle_outline,
        label: l10n.torStatePaused,
      ),
      TorrentState.finished => TorrentStateView(
        rowState: ProgressRowState.paused,
        icon: Icons.check_circle_outline,
        label: l10n.torStateFinished,
      ),
      TorrentState.error => TorrentStateView(
        rowState: ProgressRowState.error,
        icon: Icons.error_outline,
        label: l10n.torStateError,
      ),
      TorrentState.unknown => TorrentStateView(
        rowState: ProgressRowState.idle,
        icon: Icons.help_outline,
        label: l10n.torStateUnknown,
      ),
    };
