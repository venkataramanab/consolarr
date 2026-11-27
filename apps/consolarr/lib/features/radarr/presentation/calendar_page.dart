// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Calendar (RAD-10): cinema, digital and physical dates by day, filtered by
/// type. Cached for the offline view.
class CalendarPage extends ConsumerWidget {
  const CalendarPage({required this.padding, super.key});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(calendarProvider);
    final types = ref.watch(calendarTypesProvider);
    final now = ref.watch(clockProvider)();
    Future<void> refresh() => ref.read(calendarProvider.notifier).refresh();

    Widget pane(Widget child) => RefreshIndicator(
      onRefresh: refresh,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.maxHeight - padding.vertical,
            ),
            child: child,
          ),
        ),
      ),
    );

    final Widget body;
    if (async.isLoading) {
      body = ListSkeleton(padding: padding);
    } else if (async.hasError || async.value == null) {
      body = pane(
        radarrErrorView(
          context,
          const AppError(ErrorCategory.parseError),
          onRetry: refresh,
        ),
      );
    } else {
      body = switch (async.value!) {
        RadarrNoServer() || RadarrGone() => pane(radarrNoServerView(context)),
        RadarrFailure(:final error) => pane(
          radarrErrorView(context, error, onRetry: refresh),
        ),
        RadarrData(:final snapshot) => _list(
          context,
          ref,
          snapshot,
          types,
          now,
          refresh,
        ),
      };
    }
    return RadarrScreenView(screen: ScreenName.radarrCalendar, child: body);
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    Snapshot<List<RadarrMovie>> snapshot,
    Set<ReleaseType> types,
    DateTime now,
    Future<void> Function() refresh,
  ) {
    final l10n = context.l10n;
    final (start, end) = calendarRange(now);
    final entries = calendarEntries(
      snapshot.value,
      types,
      from: start,
      to: end,
    );
    final theme = Theme.of(context);
    final days = <DateTime, List<CalendarEntry>>{};
    for (final e in entries) {
      final local = e.date.toLocal();
      days
          .putIfAbsent(DateTime(local.year, local.month, local.day), () => [])
          .add(e);
    }
    final dayKeys = days.keys.toList();
    final today = DateTime(now.year, now.month, now.day);
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          if (snapshot.isOffline)
            Padding(
              padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: offlineBanner(
                context,
                fetchedAt: snapshot.fetchedAt,
                now: now,
                onRetry: refresh,
              ),
            ),
          Wrap(
            spacing: ConsolarrSpacing.sm,
            children: [
              for (final t in ReleaseType.values)
                FilterChip(
                  avatar: Icon(releaseTypeIcon(t), size: 18),
                  label: Text(releaseTypeText(l10n, t)),
                  selected: types.contains(t),
                  onSelected: (_) =>
                      ref.read(calendarTypesProvider.notifier).toggle(t),
                ),
            ],
          ),
          if (entries.isEmpty)
            SizedBox(
              height: 320,
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                headline: l10n.radarrCalendarEmptyHeadline,
                message: l10n.radarrCalendarEmptyMessage,
              ),
            )
          else
            for (final day in dayKeys) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: ConsolarrSpacing.md,
                  bottom: ConsolarrSpacing.xs,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    day == today
                        ? l10n.radarrCalendarToday(day)
                        : l10n.radarrCalendarDay(day),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              for (final e in days[day]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                  child: MediaListTile(
                    key: ValueKey('${e.movie.id}-${e.type.name}'),
                    title: e.movie.title,
                    metadata: [
                      releaseTypeText(l10n, e.type),
                      if (e.movie.year != null) '${e.movie.year}',
                    ],
                    semanticsLabel: l10n.radarrCalendarSemantics(
                      e.movie.title,
                      releaseTypeText(l10n, e.type),
                    ),
                    onTap: () => openMovie(context, e.movie.id),
                    trailing: StatusChip(
                      label: releaseTypeText(l10n, e.type),
                      icon: releaseTypeIcon(e.type),
                      tone: StatusTone.info,
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
