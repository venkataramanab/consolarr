// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:consolarr/shared/logging/log_events.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Top bar button that opens the [ServerSwitcherSheet] for [kinds] (NAV-02).
///
/// With several kinds (torrents) the sheet shows each server's kind label and
/// remembers the chosen kind under [selectionKey] in `AppStateRows`.
class ServerSwitcherButton extends StatelessWidget {
  const ServerSwitcherButton({
    required this.kinds,
    this.selectionKey,
    super.key,
  });

  final Set<ServiceKind> kinds;

  /// `AppStateRows` key that stores the kind of the last chosen server.
  final String? selectionKey;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.switcherTooltip,
      icon: const Icon(Icons.swap_horiz),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) =>
            ServerSwitcherSheet(kinds: kinds, selectionKey: selectionKey),
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

/// The kind stored under [key] in `AppStateRows`, live.
final _selectedKindProvider = StreamProvider.autoDispose
    .family<ServiceKind?, String>((ref, key) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.appStateRows,
      )..where((r) => r.key.equals(key))).watchSingleOrNull().map((row) {
        for (final k in ServiceKind.values) {
          if (k.name == row?.value) return k;
        }
        return null;
      });
    });

/// Lists the servers of the given kinds with a health dot and name (and the
/// kind label when several kinds are listed); selecting one makes it the
/// active server of its kind (offline servers are marked).
class ServerSwitcherSheet extends ConsumerWidget {
  const ServerSwitcherSheet({
    required this.kinds,
    this.selectionKey,
    super.key,
  });

  final Set<ServiceKind> kinds;
  final String? selectionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final servers = (ref.watch(uiServersProvider).value ?? const [])
        .where((s) => kinds.contains(s.profile.kind))
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
                child: _ServerList(
                  kinds: kinds,
                  selectionKey: selectionKey,
                  servers: servers,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServerList extends ConsumerWidget {
  const _ServerList({
    required this.kinds,
    required this.selectionKey,
    required this.servers,
  });

  final Set<ServiceKind> kinds;
  final String? selectionKey;
  final List<ServerEntry> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final multi = kinds.length > 1;
    final selected = selectionKey == null
        ? null
        : ref.watch(_selectedKindProvider(selectionKey!)).value;
    // The chosen kind wins; before any choice the first listed kind with an
    // active server is the one the screen shows (registry order).
    ServiceKind? current = selected;
    if (multi && (current == null || !kinds.contains(current))) {
      for (final k in kinds) {
        if (ref.watch(activeConnectionKeyProvider(k)).value?.serverId != null) {
          current = k;
          break;
        }
      }
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final entry in servers)
          _ServerTile(
            entry: entry,
            isActive:
                entry.profile.id ==
                    ref
                        .watch(activeConnectionKeyProvider(entry.profile.kind))
                        .value
                        ?.serverId &&
                (!multi || entry.profile.kind == current),
            activeLabel: l10n.switcherActive,
            kindLabel: multi
                ? serviceKindLabel(l10n, entry.profile.kind)
                : null,
            onTap: () async {
              final kind = entry.profile.kind;
              final key = selectionKey;
              // The server becomes active first, the kind is stored second:
              // the screen then switches once, straight to the chosen server.
              // (The other order showed the new kind's previously active
              // server for a moment.)
              await ref
                  .read(serverRepositoryProvider)
                  .setActive(kind, entry.profile.id);
              logServerSwitch(ref.read(loggerProvider), kind);
              if (multi && key != null) {
                final db = ref.read(databaseProvider);
                await db
                    .into(db.appStateRows)
                    .insertOnConflictUpdate(
                      AppStateRowsCompanion.insert(key: key, value: kind.name),
                    );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}

class _ServerTile extends ConsumerWidget {
  const _ServerTile({
    required this.entry,
    required this.isActive,
    required this.activeLabel,
    required this.onTap,
    this.kindLabel,
  });

  final ServerEntry entry;
  final bool isActive;
  final String activeLabel;
  final String? kindLabel;
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
      subtitle: Text(
        joinParts(l10n, [
          if (kindLabel != null) kindLabel!,
          if (isActive) activeLabel,
          label,
        ]),
      ),
      trailing: isActive ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
