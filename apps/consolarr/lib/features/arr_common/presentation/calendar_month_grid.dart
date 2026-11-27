// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// A hand-built month grid: weekday header and one cell per day, with a
/// marker (count) on days that have items. Kind-agnostic: takes plain values
/// and localized strings only.
///
/// Seven cells share the width: each is at least [minCellWidth] (40dp) wide
/// and at least [minCellHeight] (48dp) high, so a 320dp phone fits the whole
/// month without sideways scrolling. A cell is a little narrower than the
/// 48dp Material target below about 368dp of grid width; the height stays
/// 48dp and grows with the text scale. Only a grid narrower than 280dp
/// scrolls. Days are labelled for screen readers (date and count), the
/// selected day is marked as selected and today carries a ring, so state is
/// never colour alone.
class ArrMonthGrid extends StatelessWidget {
  const ArrMonthGrid({
    required this.year,
    required this.month,
    required this.firstWeekday,
    required this.weekdayLabels,
    required this.counts,
    required this.dayLabel,
    required this.dayText,
    required this.onSelect,
    this.today,
    this.selected,
    this.todayMarker = '',
    super.key,
  });

  final int year;
  final int month;

  /// Day the week starts on: 0 = Sunday ... 6 = Saturday (as in
  /// `MaterialLocalizations.firstDayOfWeekIndex`).
  final int firstWeekday;

  /// Seven narrow weekday names starting with Sunday.
  final List<String> weekdayLabels;

  /// Items per day of month (1-based); absent or 0 = none.
  final Map<int, int> counts;

  /// Accessible label of a day, including its count.
  final String Function(int day, int count) dayLabel;

  /// The day number as shown (locale digits).
  final String Function(int day) dayText;
  final ValueChanged<int> onSelect;

  /// Day of month that is today, when it is in this month.
  final int? today;
  final int? selected;

  /// Spoken marker appended to today's label (for example "today").
  final String todayMarker;

  static const double minCellWidth = 40;
  static const double minCellHeight = 48;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Dart weekday: Monday = 1 ... Sunday = 7; convert to Sunday = 0.
    final firstOfMonth = DateTime(year, month).weekday % 7;
    final lead = (firstOfMonth - firstWeekday + 7) % 7;
    final rows = ((lead + daysInMonth) / 7).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final needed = minCellWidth * 7;
        final width = constraints.maxWidth < needed
            ? needed
            : constraints.maxWidth;
        final grid = SizedBox(
          width: width,
          child: Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: ExcludeSemantics(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              weekdayLabels[(firstWeekday + i) % 7],
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      Expanded(
                        child: _cell(
                          context,
                          r * 7 + c - lead + 1,
                          daysInMonth,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
        return constraints.maxWidth < needed
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: grid,
              )
            : grid;
      },
    );
  }

  Widget _cell(BuildContext context, int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: minCellHeight);
    }
    final roles = context.roles;
    final theme = Theme.of(context);
    final count = counts[day] ?? 0;
    final isSelected = selected == day;
    final isToday = today == day;
    final label = isToday
        ? '${dayLabel(day, count)}, $todayMarker'
        : dayLabel(day, count);
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      onTap: () => onSelect(day),
      child: InkWell(
        onTap: () => onSelect(day),
        borderRadius: ConsolarrRadii.card,
        // The height follows the text (no clamp), never below 48dp.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minCellHeight),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isSelected ? roles.raised : null,
                borderRadius: ConsolarrRadii.card,
                border: isToday
                    ? Border.all(color: roles.accent, width: 2)
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        dayText(day),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    // A dot (count > 0) or a short bar (several), plus the
                    // count is in the semantics label.
                    SizedBox(
                      height: 6,
                      child: count == 0
                          ? null
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: roles.accent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: SizedBox(width: count > 1 ? 16 : 6),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
