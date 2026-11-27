// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/calendar_month_grid.dart';
import 'package:consolarr/features/sonarr/application/calendar_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_episode_row.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_error_view.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The calendar tab body (SON-13): range list or month grid, every state.
class CalendarBody extends ConsumerWidget {
  const CalendarBody({required this.padding, this.onOpenServers, super.key});

  final EdgeInsets padding;
  final void Function(BuildContext context)? onOpenServers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final calendar = ref.watch(calendarProvider);
    final view = ref.watch(calendarViewProvider);
    Future<void> refresh() => ref.read(calendarProvider.notifier).refresh();

    Widget pane(Widget child) => RefreshIndicator(
      edgeOffset: padding.top,
      onRefresh: refresh,
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: child,
      ),
    );

    // Order matters: the previous server's value survives reloads/errors.
    if (calendar.isLoading) {
      return _Skeleton(padding: padding, label: l10n.sonarrCalendarLoading);
    }
    if (calendar.hasError) {
      return pane(
        SonarrErrorView.unexpected(
          title: l10n.sonarrCalendarErrorTitle,
          onRetry: refresh,
        ),
      );
    }
    final state = calendar.value;
    return switch (state) {
      null => _Skeleton(padding: padding, label: l10n.sonarrCalendarLoading),
      CalendarNoServer() => pane(
        SonarrErrorView.noServer(
          onOpenServers: () => onOpenServers?.call(context),
        ),
      ),
      CalendarFailure(:final error) => pane(
        SonarrErrorView(
          title: l10n.sonarrCalendarErrorTitle,
          error: error,
          onRetry: refresh,
          onOpenServers: onOpenServers == null
              ? null
              : () => onOpenServers!(context),
        ),
      ),
      CalendarData() => RefreshIndicator(
        edgeOffset: padding.top,
        onRefresh: refresh,
        child: _Content(
          data: state,
          view: view,
          padding: padding,
          onRetry: refresh,
        ),
      ),
    };
  }
}

void _open(BuildContext context, int seriesId) =>
    GoRouter.maybeOf(context)?.push(sonarrSeriesLocation(seriesId));

class _Content extends ConsumerWidget {
  const _Content({
    required this.data,
    required this.view,
    required this.padding,
    required this.onRetry,
  });

  final CalendarData data;
  final CalendarView view;
  final EdgeInsets padding;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final now = ref.watch(clockProvider)();
    final source = ref.watch(artworkSourceProvider);
    final notifier = ref.read(calendarViewProvider.notifier);
    final groups = groupByDay(data.snapshot.episodes);
    final today = DateTime(now.year, now.month, now.day);
    final inset = EdgeInsets.only(left: padding.left, right: padding.right);
    final isMonth = view.mode == CalendarMode.month;

    Widget row(SonarrEpisode e) => Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
      child: CalendarEpisodeRow(
        key: ValueKey(e.id),
        episode: e,
        source: source,
        now: now,
        onOpen: () => _open(context, e.seriesId),
      ),
    );

    final slivers = <Widget>[
      SliverToBoxAdapter(child: SizedBox(height: padding.top)),
      if (data.isOffline)
        SliverPadding(
          padding: inset.copyWith(bottom: ConsolarrSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: OfflineBanner(
              message: l10n.sonarrOfflineMessage,
              ageText: l10n.sonarrUpdatedAgo(
                ageText(l10n, now.difference(data.snapshot.fetchedAt)),
              ),
              retryLabel: l10n.sonarrRetry,
              onRetry: onRetry,
            ),
          ),
        ),
      SliverPadding(
        padding: inset.copyWith(bottom: ConsolarrSpacing.sm),
        sliver: SliverToBoxAdapter(
          child: isMonth
              ? _MonthNav(view: view, onStep: notifier.step)
              : _RangeNav(view: view, onStep: notifier.step),
        ),
      ),
    ];

    if (isMonth) {
      final counts = <int, int>{
        for (final e in groups.entries)
          if (e.key.year == view.anchor.year &&
              e.key.month == view.anchor.month)
            e.key.day: e.value.length,
      };
      final selected = view.selectedDay;
      final dayEpisodes = selected == null
          ? null
          : groups[selected] ?? const [];
      slivers
        ..add(
          SliverPadding(
            padding: inset.copyWith(bottom: ConsolarrSpacing.md),
            sliver: SliverToBoxAdapter(
              child: _Grid(
                view: view,
                counts: counts,
                today: today,
                onSelect: (d) => notifier.selectDay(
                  DateTime(view.anchor.year, view.anchor.month, d),
                ),
              ),
            ),
          ),
        )
        ..add(
          dayEpisodes == null || dayEpisodes.isEmpty
              ? SliverPadding(
                  padding: inset,
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      dayEpisodes == null
                          ? l10n.sonarrCalendarPickDay
                          : l10n.sonarrCalendarEmptyDay,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              : SliverPadding(
                  padding: inset,
                  sliver: SliverList.builder(
                    itemCount: dayEpisodes.length,
                    itemBuilder: (context, i) => row(dayEpisodes[i]),
                  ),
                ),
        );
    } else if (groups.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          child: EmptyState(
            icon: Icons.event_busy_outlined,
            headline: l10n.sonarrCalendarEmptyRangeHeadline,
            message: l10n.sonarrCalendarEmptyRangeMessage,
          ),
        ),
      );
    } else {
      // One flat, lazily built list: a header per day, then its rows.
      final items = <Object>[
        for (final entry in groups.entries) ...[entry.key, ...entry.value],
      ];
      slivers.add(
        SliverPadding(
          padding: inset,
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is DateTime) {
                return _DayHeader(day: item, isToday: item == today);
              }
              return row(item as SonarrEpisode);
            },
          ),
        ),
      );
    }
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: padding.bottom)));
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ConsolarrSpacing.sm),
        child: Text(
          isToday
              ? l10n.sonarrCalendarTodayHeader(day)
              : l10n.sonarrCalendarDayHeader(day),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}

/// Earlier / range / later controls of the list view: the range on top,
/// the two buttons below (they never compete for width).
class _RangeNav extends StatelessWidget {
  const _RangeNav({required this.view, required this.onStep});

  final CalendarView view;
  final void Function(int direction) onStep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final last = view.end.subtract(const Duration(days: 1));
    return Column(
      children: [
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            l10n.sonarrCalendarRange(view.start, last),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => onStep(-1),
              icon: const Icon(Icons.chevron_left),
              label: Text(l10n.sonarrCalendarEarlier),
            ),
            TextButton.icon(
              onPressed: () => onStep(1),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right),
              label: Text(l10n.sonarrCalendarLater),
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.view, required this.onStep});

  final CalendarView view;
  final void Function(int direction) onStep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        IconButton(
          tooltip: l10n.sonarrCalendarPreviousMonth,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onStep(-1),
        ),
        Expanded(
          child: Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              l10n.sonarrCalendarMonthTitle(view.start),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.sonarrCalendarNextMonth,
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onStep(1),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.view,
    required this.counts,
    required this.today,
    required this.onSelect,
  });

  final CalendarView view;
  final Map<int, int> counts;
  final DateTime today;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final material = MaterialLocalizations.of(context);
    final y = view.anchor.year;
    final m = view.anchor.month;
    return ArrMonthGrid(
      year: y,
      month: m,
      firstWeekday: material.firstDayOfWeekIndex,
      weekdayLabels: material.narrowWeekdays,
      counts: counts,
      today: today.year == y && today.month == m ? today.day : null,
      selected: view.selectedDay?.month == m && view.selectedDay?.year == y
          ? view.selectedDay!.day
          : null,
      todayMarker: l10n.sonarrCalendarToday,
      dayLabel: (day, count) =>
          l10n.sonarrCalendarDaySemantics(DateTime(y, m, day), count),
      dayText: l10n.sonarrCalendarDayNumber,
      onSelect: onSelect,
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.padding, required this.label});

  final EdgeInsets padding;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          children: [
            for (var i = 0; i < 6; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: SkeletonBox(
                  height: 88,
                  borderRadius: ConsolarrRadii.card,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
