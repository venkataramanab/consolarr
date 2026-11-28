// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_format.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_widgets.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// DSH-02: what is downloading right now. Live: never cached.
class ActivityCard extends ConsumerWidget {
  const ActivityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Only this card's own state: a change in another card rebuilds nothing
    // here.
    final state = ref.watch(dashboardProvider.select((s) => s.activity));
    return DashboardCardFrame(
      heading: l10n.dashboardActivityHeading,
      child: switch (state) {
        CardLoading() => const DashboardSkeleton(carousel: false),
        CardNotConfigured() => DashboardCardMessage(
          icon: Icons.downloading_outlined,
          headline: l10n.dashboardActivityNotConfigured,
          actionLabel: l10n.dashboardSetupCta,
          onAction: () => openSetup(context),
        ),
        CardEmpty() => DashboardCardMessage(
          icon: Icons.download_done_outlined,
          headline: l10n.dashboardActivityEmptyHeading,
          message: l10n.dashboardActivityEmptyBody,
        ),
        CardError(:final slices) => _Slices(slices: slices),
        CardData(:final slices) => _Slices(slices: slices),
      },
    );
  }
}

class _Slices extends StatelessWidget {
  const _Slices({required this.slices});

  final List<CardSlice<ActivitySummary>> slices;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, slice) in slices.indexed) ...[
        if (i > 0) const SizedBox(height: ConsolarrSpacing.md),
        // A repaint boundary per live server: a poll repaints only what
        // changed.
        RepaintBoundary(
          key: ValueKey(slice.serverId),
          child: switch (slice) {
            SliceData<ActivitySummary>() => _ActivitySlice(slice: slice),
            SliceFailed<ActivitySummary>() => DashboardSliceError(
              slice: slice,
              card: DashboardCard.activity,
            ),
            SliceLoading<ActivitySummary>() => const DashboardSkeleton(
              carousel: false,
            ),
          },
        ),
      ],
    ],
  );
}

class _ActivitySlice extends ConsumerWidget {
  const _ActivitySlice({required this.slice});

  final SliceData<ActivitySummary> slice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final roles = context.roles;
    final theme = Theme.of(context);
    final summary = slice.value;
    final service = serviceTitle(l10n, slice.kind, slice.serverName);
    void open() =>
        openDashboardLink(context, ref, DashboardCard.activity, summary.link);
    final lines = <String>[
      if (summary.active > 0 || summary.attention == 0)
        l10n.dashboardActivityActive(summary.active),
      if (summary.attention > 0)
        l10n.dashboardActivityAttention(summary.attention),
    ];
    final hasSpeed = summary.downSpeed != null || summary.upSpeed != null;
    final speeds = [
      if (summary.downSpeed != null)
        l10n.dashboardSpeedDown(formatSpeed(l10n, summary.downSpeed!)),
      if (summary.upSpeed != null)
        l10n.dashboardSpeedUp(formatSpeed(l10n, summary.upSpeed!)),
    ];
    String join(List<String> parts) => parts.reduce(l10n.dashboardSpokenJoin);
    final counts = join(lines);
    // The whole tile is one button: the service, the counts and the speeds are
    // what is read; "Open" is its hint.
    final spoken = hasSpeed
        ? l10n.dashboardActivitySemanticsSpeeds(service, counts, join(speeds))
        : l10n.dashboardActivitySemantics(service, counts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          label: spoken,
          hint: l10n.dashboardOpenHint,
          excludeSemantics: true,
          onTap: open,
          child: Material(
            color: roles.card,
            borderRadius: ConsolarrRadii.card,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: open,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ConsolarrSpacing.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(ConsolarrSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ServiceHeading(kind: slice.kind, name: slice.serverName),
                      for (final line in lines)
                        Text(line, style: theme.textTheme.bodyMedium),
                      if (hasSpeed)
                        Wrap(
                          spacing: ConsolarrSpacing.md,
                          children: [
                            for (final text in speeds)
                              Text(text, style: theme.textTheme.bodyMedium),
                          ],
                        )
                      else if (summary.speedUnavailable)
                        Text(
                          l10n.dashboardSpeedUnavailable,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final row in summary.rows) ...[
          const SizedBox(height: ConsolarrSpacing.sm),
          _ActivityRowView(row: row, onTap: open),
        ],
      ],
    );
  }
}

class _ActivityRowView extends StatelessWidget {
  const _ActivityRowView({required this.row, required this.onTap});

  final ActivityRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (rowState, icon, label) = activityStyle(l10n, row.state);
    return ProgressFillRow(
      title: row.title,
      progress: row.progress,
      state: rowState,
      stateIcon: icon,
      stateLabel: label,
      progressLabel: l10n.dashboardProgressPercent(row.progress),
      semanticsLabel: l10n.dashboardRowSemantics(
        row.title,
        label,
        l10n.dashboardProgressSpoken(row.progress),
      ),
      details: [
        if (row.speed != null && row.speed! > 0) formatSpeed(l10n, row.speed!),
        if (row.sizeLeft != null && row.sizeLeft! > 0)
          l10n.dashboardRowLeft(formatBytes(l10n, row.sizeLeft!)),
        if (row.eta != null)
          l10n.dashboardRowEta(formatDuration(l10n, row.eta!)),
      ],
      onTap: onTap,
    );
  }
}
