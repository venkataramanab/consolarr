// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One choice in a [FilterSection].
class FilterChipOption {
  const FilterChipOption({required this.id, required this.label});
  final String id;
  final String label;
}

/// A group of chips (single or multi select).
///
/// `initial` is a stand-in addition: the ids selected when the sheet opens.
class FilterSection {
  const FilterSection({
    required this.id,
    required this.label,
    required this.chips,
    this.multiSelect = true,
    this.initial = const {},
  });

  final String id;
  final String label;
  final List<FilterChipOption> chips;
  final bool multiSelect;
  final Set<String> initial;
}

/// The chosen chip ids per section id.
class FilterSelection {
  const FilterSelection(this.chosen);
  final Map<String, Set<String>> chosen;

  Set<String> of(String sectionId) => chosen[sectionId] ?? const {};
}

/// Stand-in with the contract of W4d's `FilterSheet`.
///
/// TODO(w4d): replace with `design_system`'s `FilterSheet` once W4d has merged.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    required this.title,
    required this.sections,
    required this.activeCount,
    required this.clearAllLabel,
    required this.saveAsDefaultLabel,
    required this.applyLabel,
    required this.onApply,
    required this.onClear,
    super.key,
  });

  final String title;
  final List<FilterSection> sections;
  final int activeCount;
  final String clearAllLabel;
  final String saveAsDefaultLabel;
  final String applyLabel;
  final void Function(FilterSelection selection, bool saveAsDefault) onApply;
  final VoidCallback onClear;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final Map<String, Set<String>> _chosen = {
    for (final s in widget.sections) s.id: {...s.initial},
  };
  bool _save = false;

  void _toggle(FilterSection section, String id) {
    setState(() {
      final set = _chosen[section.id]!;
      if (set.contains(id)) {
        set.remove(id);
      } else {
        if (!section.multiSelect) set.clear();
        set.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.lg,
        0,
        ConsolarrSpacing.lg,
        ConsolarrSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in widget.sections) ...[
            Semantics(
              header: true,
              child: Text(section.label, style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: ConsolarrSpacing.xs),
            Wrap(
              spacing: ConsolarrSpacing.sm,
              children: [
                for (final chip in section.chips)
                  FilterChip(
                    key: ValueKey('filter-${section.id}-${chip.id}'),
                    label: Text(chip.label),
                    selected: _chosen[section.id]!.contains(chip.id),
                    onSelected: (_) => _toggle(section, chip.id),
                  ),
              ],
            ),
            const SizedBox(height: ConsolarrSpacing.md),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.saveAsDefaultLabel),
            value: _save,
            onChanged: (v) => setState(() => _save = v),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClear,
                  child: Text(widget.clearAllLabel),
                ),
              ),
              const SizedBox(width: ConsolarrSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      widget.onApply(FilterSelection(_chosen), _save),
                  child: Text(widget.applyLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
