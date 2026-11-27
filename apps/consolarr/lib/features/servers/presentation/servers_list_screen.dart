// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/application/servers_ui_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/screen_tracking.dart';
import 'package:consolarr/features/servers/presentation/servers_routes.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

enum _RowAction {
  edit,
  setActive,
  setStartup,
  clearStartup,
  moveUp,
  moveDown,
  delete,
}

/// The servers list (SRV-01, SRV-07, SRV-10).
class ServersListScreen extends ConsumerWidget {
  const ServersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final servers = ref.watch(serversProvider);
    return ScreenViewTracker(
      screen: ScreenName.serversList,
      child: FloatingTopBarScaffold(
        title: l10n.serversTitle,
        actions: [
          IconButton(
            tooltip: l10n.serversAddTooltip,
            icon: const Icon(Icons.add),
            onPressed: () => context.push(ServersRoutes.newServer),
          ),
        ],
        bodyBuilder: (context, padding) => servers.when(
          loading: () => _Skeleton(padding: padding),
          error: (e, _) => Padding(
            padding: padding,
            child: ErrorState(
              headline: l10n.serversLoadErrorHeadline,
              message: l10n.serversLoadErrorMessage,
              retryLabel: l10n.serversRetry,
              onRetry: () => ref.invalidate(serversProvider),
            ),
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: padding,
                  child: EmptyState(
                    icon: Icons.dns_outlined,
                    headline: l10n.serversEmptyHeadline,
                    message: l10n.serversEmptyMessage,
                    actionLabel: l10n.serversEmptyAction,
                    onAction: () => context.push(ServersRoutes.onboarding),
                  ),
                )
              : _ServerList(entries: list, padding: padding),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: ConsolarrSpacing.md),
      itemBuilder: (_, _) => const SkeletonBox(height: 84),
    );
  }
}

class _ServerList extends ConsumerWidget {
  const _ServerList({required this.entries, required this.padding});

  final List<ServerEntry> entries;
  final EdgeInsets padding;

  Future<void> _move(WidgetRef ref, int from, int to) async {
    if (to < 0 || to >= entries.length) return;
    final ids = [for (final e in entries) e.profile.id];
    ids.insert(to, ids.removeAt(from));
    await ref.read(serverRepositoryProvider).reorder(ids);
  }

  Future<void> _refresh(WidgetRef ref) async {
    for (final e in entries) {
      ref.invalidate(serverHealthProvider(e.profile.id));
    }
    ref.invalidate(activeServerIdsProvider);
    await Future.wait([
      for (final e in entries)
        ref
            .read(serverHealthProvider(e.profile.id).future)
            .then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeServerIdsProvider).value ?? const {};
    return RefreshIndicator(
      edgeOffset: padding.top,
      onRefresh: () => _refresh(ref),
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: padding,
        itemCount: entries.length,
        onReorderItem: (from, to) => _move(ref, from, to),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _ServerRow(
            key: ValueKey(entry.profile.id),
            entry: entry,
            index: index,
            isFirst: index == 0,
            isLast: index == entries.length - 1,
            isActive: active.contains(entry.profile.id),
            onMove: (delta) => _move(ref, index, index + delta),
          );
        },
      ),
    );
  }
}

class _ServerRow extends ConsumerWidget {
  const _ServerRow({
    required this.entry,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.isActive,
    required this.onMove,
    super.key,
  });

  final ServerEntry entry;
  final int index;
  final bool isFirst;
  final bool isLast;
  final bool isActive;
  final ValueChanged<int> onMove;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final name = entry.profile.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverDeleteTitle(name)),
        content: Text(l10n.serverDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.serversCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.serverDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(serverRepositoryProvider).delete(entry.profile.id);
    }
  }

  Future<void> _run(BuildContext context, WidgetRef ref, _RowAction a) async {
    final repo = ref.read(serverRepositoryProvider);
    final id = entry.profile.id;
    switch (a) {
      case _RowAction.edit:
        await context.push(ServersRoutes.edit(id));
      case _RowAction.setActive:
        await repo.setActive(entry.profile.kind, id);
        ref.invalidate(activeServerIdsProvider);
      case _RowAction.setStartup:
        await repo.setStartup(id);
      case _RowAction.clearStartup:
        await repo.setStartup(null);
      case _RowAction.moveUp:
        onMove(-1);
      case _RowAction.moveDown:
        onMove(1);
      case _RowAction.delete:
        await _delete(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final p = entry.profile;
    final health = ref.watch(serverHealthProvider(p.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
      child: Material(
        color: context.roles.card,
        borderRadius: ConsolarrRadii.card,
        child: InkWell(
          borderRadius: ConsolarrRadii.card,
          onTap: () => context.push(ServersRoutes.edit(p.id)),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: ConsolarrSpacing.lg,
              top: ConsolarrSpacing.md,
              bottom: ConsolarrSpacing.md,
              end: ConsolarrSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(serviceKindIcon(p.kind))),
                const SizedBox(width: ConsolarrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        serviceKindLabel(l10n, p.kind),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: ConsolarrSpacing.sm),
                      Wrap(
                        spacing: ConsolarrSpacing.sm,
                        runSpacing: ConsolarrSpacing.xs,
                        children: [
                          _healthChip(l10n, health),
                          if (!p.isSecure && p.allowCleartext)
                            StatusChip(
                              label: l10n.serverBadgeCleartext,
                              icon: Icons.lock_open_outlined,
                              tone: StatusTone.warning,
                            ),
                          if (entry.needsCredentials)
                            StatusChip(
                              label: l10n.serverBadgeNeedsCredentials,
                              icon: Icons.key_off_outlined,
                              tone: StatusTone.warning,
                            ),
                          if (isActive)
                            StatusChip(
                              label: l10n.serverBadgeActive,
                              icon: Icons.check,
                              tone: StatusTone.info,
                            ),
                          if (entry.isStartup)
                            StatusChip(
                              label: l10n.serverBadgeStartup,
                              icon: Icons.rocket_launch_outlined,
                              tone: StatusTone.neutral,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_RowAction>(
                  tooltip: l10n.serverMenuTooltip(p.name),
                  onSelected: (a) => _run(context, ref, a),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _RowAction.edit,
                      child: Text(l10n.serverActionEdit),
                    ),
                    if (!isActive)
                      PopupMenuItem(
                        value: _RowAction.setActive,
                        child: Text(l10n.serverActionSetActive),
                      ),
                    PopupMenuItem(
                      value: entry.isStartup
                          ? _RowAction.clearStartup
                          : _RowAction.setStartup,
                      child: Text(
                        entry.isStartup
                            ? l10n.serverActionClearStartup
                            : l10n.serverActionSetStartup,
                      ),
                    ),
                    if (!isFirst)
                      PopupMenuItem(
                        value: _RowAction.moveUp,
                        child: Text(l10n.serverActionMoveUp),
                      ),
                    if (!isLast)
                      PopupMenuItem(
                        value: _RowAction.moveDown,
                        child: Text(l10n.serverActionMoveDown),
                      ),
                    PopupMenuItem(
                      value: _RowAction.delete,
                      child: Text(l10n.serverActionDelete),
                    ),
                  ],
                ),
                Semantics(
                  label: l10n.serverDragHandleLabel(p.name),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: const SizedBox.square(
                      dimension: ConsolarrSpacing.minTapTarget,
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _healthChip(AppLocalizations l10n, AsyncValue<ServerHealth> health) {
    return health.when(
      loading: () => StatusChip(
        label: l10n.serverHealthChecking,
        icon: Icons.hourglass_empty,
        tone: StatusTone.neutral,
      ),
      error: (_, _) => StatusChip(
        label: l10n.serverHealthUnknown,
        icon: Icons.help_outline,
        tone: StatusTone.neutral,
      ),
      data: (h) => switch (h) {
        ServerHealth.checking => StatusChip(
          label: l10n.serverHealthChecking,
          icon: Icons.hourglass_empty,
          tone: StatusTone.neutral,
        ),
        ServerHealth.healthy => StatusChip(
          label: l10n.serverHealthHealthy,
          icon: Icons.check_circle_outline,
          tone: StatusTone.success,
        ),
        ServerHealth.degraded => StatusChip(
          label: l10n.serverHealthDegraded,
          icon: Icons.warning_amber_rounded,
          tone: StatusTone.warning,
        ),
        ServerHealth.unauthorized => StatusChip(
          label: l10n.serverHealthUnauthorized,
          icon: Icons.lock_outline,
          tone: StatusTone.error,
        ),
        ServerHealth.unreachable => StatusChip(
          label: l10n.serverHealthUnreachable,
          icon: Icons.cloud_off_outlined,
          tone: StatusTone.error,
        ),
      },
    );
  }
}
