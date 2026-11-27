// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrent_view.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

String torrentTabLabel(AppLocalizations l10n, TorrentTab tab) => switch (tab) {
  TorrentTab.all => l10n.torTabAll,
  TorrentTab.active => l10n.torTabActive,
  TorrentTab.downloading => l10n.torTabDownloading,
  TorrentTab.finished => l10n.torTabFinished,
  TorrentTab.error => l10n.torTabError,
};

/// The status tabs (all, active, downloading, finished, error). The selected
/// one shows a check mark as well as its fill.
class StatusTabs extends StatelessWidget {
  const StatusTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final TorrentTab selected;
  final ValueChanged<TorrentTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.torTabsLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in TorrentTab.values)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: ConsolarrSpacing.sm,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ConsolarrSpacing.minTapTarget,
                  ),
                  child: ChoiceChip(
                    label: Text(torrentTabLabel(l10n, tab)),
                    selected: tab == selected,
                    showCheckmark: true,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => onSelected(tab),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
