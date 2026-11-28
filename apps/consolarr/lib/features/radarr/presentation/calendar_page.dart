// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/group_header_row.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/dates.dart';
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
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({required this.padding, super.key});

  final EdgeInsets padding;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

/// One row of the calendar list: a day header or a movie of that day.
sealed class _Row {
  const _Row();
}

final class _DayRow extends _Row {
  const _DayRow(this.day, this.count);
  final DateTime day;
  final int count;
}

final class _EntryRow extends _Row {
  const _EntryRow(this.entry);
  final CalendarEntry entry;
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  /// Days the user folded away.
  final Set<DateTime> _collapsed = {};

  /// The sliver the scroll view opens on (today and the days after it).
  static const _openingKey = ValueKey<String>('calendar-opening');

  EdgeInsets get padding => widget.padding;

  @override
  Widget build(BuildContext context) {
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
    final days = <DateTime, List<CalendarEntry>>{};
    for (final e in entries) {
      // Release dates are date-only (midnight UTC): group by that day.
      days.putIfAbsent(calendarDayOf(e.date), () => []).add(e);
    }
    final today = DateTime(now.year, now.month, now.day);
    // Days before today scroll above the opening position; today and later
    // days are what the calendar opens on, soonest first.
    final earlier = <_Row>[];
    final ahead = <_Row>[];
    for (final day in days.keys) {
      final into = day.isBefore(today) ? earlier : ahead;
      into.add(_DayRow(day, days[day]!.length));
      if (!_collapsed.contains(day)) {
        into.addAll([for (final e in days[day]!) _EntryRow(e)]);
      }
    }
    // One list for everything, so a long calendar builds only what is shown.
    final head = <Widget>[
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
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) =>
                  ref.read(calendarTypesProvider.notifier).toggle(t),
            ),
        ],
      ),
    ];
    Widget buildRow(_Row row) {
      switch (row) {
        case _DayRow(:final day, :final count):
          final title = day == today
              ? l10n.radarrCalendarToday(day)
              : l10n.radarrCalendarDay(day);
          return Padding(
            padding: const EdgeInsets.only(
              top: ConsolarrSpacing.md,
              bottom: ConsolarrSpacing.xs,
            ),
            child: ArrGroupHeader(
              key: ValueKey('day-$day'),
              title: title,
              countText: l10n.radarrCalendarDayCount(count),
              expanded: !_collapsed.contains(day),
              semanticsLabel: l10n.radarrCalendarGroupSemantics(title),
              onToggle: () => setState(() {
                if (!_collapsed.remove(day)) _collapsed.add(day);
              }),
            ),
          );
        case _EntryRow(:final entry):
          return Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
            child: MediaListTile(
              key: ValueKey('${entry.movie.id}-${entry.type.name}'),
              title: entry.movie.title,
              metadata: [
                releaseTypeText(l10n, entry.type),
                if (entry.movie.year != null) '${entry.movie.year}',
              ],
              semanticsLabel: l10n.radarrCalendarSemantics(
                entry.movie.title,
                releaseTypeText(l10n, entry.type),
              ),
              onTap: () => openMovie(context, entry.movie.id),
              trailing: StatusChip(
                label: releaseTypeText(l10n, entry.type),
                icon: releaseTypeIcon(entry.type),
                tone: StatusTone.info,
              ),
            ),
          );
      }
    }

    // One scroll view with its origin ("center") at the top of today's part:
    // it opens on today with upcoming days first, and the earlier days (the
    // loaded window starts 14 days back) are reached by scrolling up. Both
    // parts are lazy slivers, so a long calendar builds only what is shown.
    final sides = EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0);
    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        center: _openingKey,
        slivers: [
          if (earlier.isNotEmpty)
            // Laid out upwards from the origin: nearest-to-today row first.
            SliverPadding(
              padding: sides.copyWith(top: padding.top),
              sliver: SliverList.builder(
                itemCount: earlier.length,
                itemBuilder: (context, i) =>
                    buildRow(earlier[earlier.length - 1 - i]),
              ),
            ),
          SliverPadding(
            key: _openingKey,
            padding: sides.copyWith(bottom: padding.bottom),
            sliver: SliverList.builder(
              // The bar inset, the filters, then upcoming rows (or the empty
              // state when nothing is in the window).
              itemCount:
                  1 +
                  head.length +
                  (entries.isEmpty || ahead.isEmpty ? 1 : ahead.length),
              itemBuilder: (context, i) {
                if (i == 0) return SizedBox(height: padding.top);
                i -= 1;
                if (i < head.length) return head[i];
                if (entries.isEmpty) {
                  return SizedBox(
                    height: 320,
                    child: EmptyState(
                      icon: Icons.event_busy_outlined,
                      headline: l10n.radarrCalendarEmptyHeadline,
                      message: l10n.radarrCalendarEmptyMessage,
                    ),
                  );
                }
                if (ahead.isEmpty) {
                  // Everything in the window is before today: say so, with
                  // the earlier days a scroll up away, instead of a blank view.
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ConsolarrSpacing.xl,
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.radarrCalendarNothingUpcoming,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  );
                }
                return buildRow(ahead[i - head.length]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
