// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/application/calendar_providers.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_body.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The calendar tab (SON-13).
final SonarrTab calendarTab = SonarrTab(
  id: 'calendar',
  icon: Icons.calendar_month_outlined,
  label: (l10n) => l10n.sonarrTabCalendar,
  body: (context, padding) => CalendarBody(
    padding: padding,
    onOpenServers: (context) => GoRouter.maybeOf(context)?.go('/servers'),
  ),
  actions: (context) => const [CalendarActions()],
);

/// Unmonitored toggle, list/month switch and jump-to-today, as top bar
/// buttons (each with a tooltip and accessible name).
class CalendarActions extends ConsumerWidget {
  const CalendarActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = ref.watch(calendarViewProvider);
    final notifier = ref.read(calendarViewProvider.notifier);
    final isMonth = view.mode == CalendarMode.month;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.sonarrCalendarToday,
          icon: const Icon(Icons.today_outlined),
          onPressed: notifier.today,
        ),
        IconButton(
          tooltip: view.includeUnmonitored
              ? l10n.sonarrCalendarHideUnmonitored
              : l10n.sonarrCalendarShowUnmonitored,
          icon: Icon(
            view.includeUnmonitored
                ? Icons.bookmark_outlined
                : Icons.bookmark_border,
          ),
          onPressed: notifier.toggleUnmonitored,
        ),
        IconButton(
          tooltip: isMonth
              ? l10n.sonarrCalendarShowList
              : l10n.sonarrCalendarShowMonth,
          icon: Icon(
            isMonth ? Icons.view_agenda_outlined : Icons.calendar_view_month,
          ),
          onPressed: () => notifier.setMode(
            isMonth ? CalendarMode.range : CalendarMode.month,
          ),
        ),
      ],
    );
  }
}
