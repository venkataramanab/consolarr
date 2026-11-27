// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Top bar button that opens the [ServerSwitcherSheet] for [kind] (NAV-02).
class ServerSwitcherButton extends StatelessWidget {
  const ServerSwitcherButton({required this.kind, super.key});

  final ServiceKind kind;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.switcherTooltip,
      icon: const Icon(Icons.swap_horiz),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => ServerSwitcherSheet(kind: kind),
      ),
    );
  }
}

String healthLabel(AppLocalizations l10n, ServerHealth health) =>
    switch (health) {
      ServerHealth.checking => l10n.healthChecking,
      ServerHealth.healthy => l10n.healthHealthy,
      ServerHealth.degraded => l10n.healthDegraded,
      ServerHealth.unauthorized => l10n.healthUnauthorized,
      ServerHealth.unreachable => l10n.healthUnreachable,
    };

IconData healthIcon(ServerHealth health) => switch (health) {
  ServerHealth.checking => Icons.sync,
  ServerHealth.healthy => Icons.check_circle_outline,
  ServerHealth.degraded => Icons.warning_amber_outlined,
  ServerHealth.unauthorized => Icons.lock_outline,
  ServerHealth.unreachable => Icons.cloud_off_outlined,
};


/// Lists the servers of one kind with a health dot and name; selecting one
/// makes it the active server (offline servers are marked).
class ServerSwitcherSheet extends ConsumerWidget {
  const ServerSwitcherSheet({required this.kind, super.key});

  final ServiceKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final servers = (ref.watch(uiServersProvider).value ?? const [])
        .where((s) => s.profile.kind == kind)
        .toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.gutter,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.switcherTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: ConsolarrSpacing.sm),
            if (servers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
                child: Text(l10n.switcherEmpty),
              )
            else
              Flexible(
                child: _ServerList(kind: kind, servers: servers),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServerList extends ConsumerWidget {
  const _ServerList({required this.kind, required this.servers});

  final ServiceKind kind;
  final List<ServerEntry> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return FutureBuilder<String?>(
      future: ref.read(serverRepositoryProvider).activeId(kind),
      builder: (context, snapshot) {
        final activeId = snapshot.data;
        return ListView(
          shrinkWrap: true,
          children: [
            for (final entry in servers)
              _ServerTile(
                entry: entry,
                isActive: entry.profile.id == activeId,
                activeLabel: l10n.switcherActive,
                onTap: () async {
                  await ref
                      .read(serverRepositoryProvider)
                      .setActive(kind, entry.profile.id);
                  ref.invalidate(activeConnectionProvider(kind));
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
        );
      },
    );
  }
}

class _ServerTile extends ConsumerWidget {
  const _ServerTile({
    required this.entry,
    required this.isActive,
    required this.activeLabel,
    required this.onTap,
  });

  final ServerEntry entry;
  final bool isActive;
  final String activeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final health = ref
        .watch(serverHealthProvider(entry.profile.id))
        .maybeWhen(data: (h) => h, orElse: () => ServerHealth.checking);
    final label = healthLabel(l10n, health);
    return ListTile(
      minTileHeight: ConsolarrSpacing.minTapTarget,
      selected: isActive,
      leading: Icon(healthIcon(health)),
      title: Text(entry.profile.name, maxLines: 2),
      subtitle: Text(isActive ? '$activeLabel · $label' : label),
      trailing: isActive ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
