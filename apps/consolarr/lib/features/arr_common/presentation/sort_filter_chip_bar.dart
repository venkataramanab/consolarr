// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// An active filter shown as a removable chip.
class ArrActiveFilter {
  const ArrActiveFilter({
    required this.id,
    required this.label,
    required this.removeLabel,
  });

  final String id;

  /// Text of the chip (for example "Monitored").
  final String label;

  /// Accessible name of the remove action (for example "Remove filter
  /// Monitored").
  final String removeLabel;
}

/// Sort and filter controls above a list (SON-03/04, RAD-03/04): a sort
/// button, a filter button with the number of active criteria, and one
/// removable chip per active filter. Plain values and localized strings only;
/// kind-agnostic.
class ArrSortFilterBar extends StatelessWidget {
  const ArrSortFilterBar({
    required this.sortLabel,
    required this.sortSemanticsLabel,
    required this.ascending,
    required this.onSort,
    required this.filterLabel,
    required this.filterSemanticsLabel,
    required this.onFilter,
    required this.activeFilters,
    required this.onRemoveFilter,
    this.clearAllLabel,
    this.onClearAll,
    super.key,
  });

  final String sortLabel;
  final String sortSemanticsLabel;
  final bool ascending;
  final VoidCallback onSort;
  final String filterLabel;
  final String filterSemanticsLabel;
  final VoidCallback onFilter;
  final List<ArrActiveFilter> activeFilters;
  final void Function(String id) onRemoveFilter;
  final String? clearAllLabel;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final active = activeFilters.isNotEmpty;
    return Wrap(
      spacing: ConsolarrSpacing.sm,
      runSpacing: ConsolarrSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          button: true,
          label: sortSemanticsLabel,
          excludeSemantics: true,
          child: ActionChip(
            avatar: Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 18,
            ),
            label: Text(sortLabel),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onPressed: onSort,
          ),
        ),
        Semantics(
          button: true,
          label: filterSemanticsLabel,
          excludeSemantics: true,
          child: ActionChip(
            avatar: const Icon(Icons.filter_list, size: 18),
            label: Text(filterLabel),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onPressed: onFilter,
          ),
        ),
        for (final f in activeFilters)
          InputChip(
            key: ValueKey('active-filter-${f.id}'),
            label: Text(f.label),
            deleteButtonTooltipMessage: f.removeLabel,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onDeleted: () => onRemoveFilter(f.id),
          ),
        if (active && clearAllLabel != null && onClearAll != null)
          TextButton(onPressed: onClearAll, child: Text(clearAllLabel!)),
      ],
    );
  }
}
