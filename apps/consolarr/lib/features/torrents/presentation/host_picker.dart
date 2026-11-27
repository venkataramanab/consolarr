// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Picks the daemon Deluge Web should connect to. Host names are server text
/// and shown as plain text only.
class DelugeHostPicker extends StatelessWidget {
  const DelugeHostPicker({
    required this.hosts,
    required this.onSelected,
    super.key,
  });

  final List<DelugeHost> hosts;
  final void Function(DelugeHost host) onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
      children: [
        Semantics(
          header: true,
          child: Text(l10n.torHostTitle, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        Text(l10n.torHostMessage),
        const SizedBox(height: ConsolarrSpacing.md),
        for (final h in hosts)
          ListTile(
            minTileHeight: ConsolarrSpacing.minTapTarget,
            leading: const Icon(Icons.dns_outlined),
            title: Text(
              l10n.torHostEntry(h.host, l10n.plainInt(h.port)),
              maxLines: 2,
            ),
            onTap: () => onSelected(h),
          ),
      ],
    );
  }
}
