// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One sort key of [ReleaseControls].
class ReleaseSortOption<K> {
  const ReleaseSortOption(this.key, this.label);

  final K key;
  final String label;
}

/// One selectable filter value.
class ReleaseFilterOption {
  const ReleaseFilterOption({
    required this.id,
    required this.label,
    required this.selected,
  });

  final String id;
  final String label;
  final bool selected;
}

/// A named group of filter chips (for example protocol or resolution).
class ReleaseFilterGroup {
  const ReleaseFilterGroup({
    required this.id,
    required this.label,
    required this.options,
  });

  final String id;
  final String label;
  final List<ReleaseFilterOption> options;
}

/// Localized strings of [ReleaseControls].
class ReleaseControlsLabels {
  const ReleaseControlsLabels({
    required this.sortButton,
    required this.reverseSort,
    required this.filterButton,
    required this.clearFilters,
  });

  /// For example "Sort: Best match" (names the current key).
  final String sortButton;

  /// Tooltip of the direction toggle.
  final String reverseSort;

  /// For example "Filters (2)".
  final String filterButton;
  final String clearFilters;
}

/// Sort menu, direction toggle and a collapsible filter panel of chips, for a
/// release list. Kind-agnostic; every control has a visible button (no
/// gesture-only action).
class ReleaseControls<K> extends StatefulWidget {
  const ReleaseControls({
    required this.labels,
    required this.sortOptions,
    required this.selectedSort,
    required this.onSort,
    required this.onReverse,
    required this.groups,
    required this.activeFilters,
    required this.onToggleFilter,
    required this.onClearFilters,
    super.key,
  });

  final ReleaseControlsLabels labels;
  final List<ReleaseSortOption<K>> sortOptions;
  final K selectedSort;
  final ValueChanged<K> onSort;
  final VoidCallback onReverse;
  final List<ReleaseFilterGroup> groups;
  final int activeFilters;
  final void Function(String groupId, String optionId) onToggleFilter;
  final VoidCallback onClearFilters;

  @override
  State<ReleaseControls<K>> createState() => _ReleaseControlsState<K>();
}

class _ReleaseControlsState<K> extends State<ReleaseControls<K>> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: ConsolarrSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<K>(
              tooltip: labels.sortButton,
              onSelected: widget.onSort,
              itemBuilder: (context) => [
                for (final o in widget.sortOptions)
                  CheckedPopupMenuItem<K>(
                    value: o.key,
                    checked: o.key == widget.selectedSort,
                    child: Text(o.label),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ConsolarrSpacing.minTapTarget,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: ConsolarrSpacing.xs),
                    Flexible(
                      child: Text(
                        labels.sortButton,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: labels.reverseSort,
              icon: const Icon(Icons.swap_vert),
              onPressed: widget.onReverse,
            ),
            TextButton.icon(
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.expand_less : Icons.filter_list),
              label: Text(labels.filterButton),
            ),
          ],
        ),
        if (_open) ...[
          for (final g in widget.groups)
            if (g.options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(g.label, style: theme.textTheme.labelMedium),
                    ),
                    Wrap(
                      spacing: ConsolarrSpacing.sm,
                      children: [
                        for (final o in g.options)
                          FilterChip(
                            label: Text(o.label),
                            selected: o.selected,
                            onSelected: (_) =>
                                widget.onToggleFilter(g.id, o.id),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          if (widget.activeFilters > 0)
            TextButton(
              onPressed: widget.onClearFilters,
              child: Text(labels.clearFilters),
            ),
        ],
      ],
    );
  }
}
