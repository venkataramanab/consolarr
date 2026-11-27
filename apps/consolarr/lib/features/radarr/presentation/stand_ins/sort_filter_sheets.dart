// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

// TODO(w4d): replace with `SortSheet` and `FilterSheet` from design_system
// once W4d has merged. Names and callbacks follow the W4d contract.

class SortOption<K> {
  const SortOption({required this.key, required this.label});
  final K key;
  final String label;
}

/// Sort keys as radio rows, a direction switch and "save as default".
class SortSheet<K> extends StatefulWidget {
  const SortSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.ascending,
    required this.ascendingLabel,
    required this.descendingLabel,
    required this.saveAsDefaultLabel,
    required this.applyLabel,
    required this.onApply,
    super.key,
  });

  final String title;
  final List<SortOption<K>> options;
  final K selected;
  final bool ascending;
  final String ascendingLabel;
  final String descendingLabel;
  final String saveAsDefaultLabel;
  final String applyLabel;
  final void Function(K key, bool ascending, bool saveAsDefault) onApply;

  @override
  State<SortSheet<K>> createState() => _SortSheetState<K>();
}

class _SortSheetState<K> extends State<SortSheet<K>> {
  late K _key = widget.selected;
  late bool _asc = widget.ascending;
  bool _save = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.lg,
      ),
      children: [
        RadioGroup<K>(
          groupValue: _key,
          onChanged: (v) => setState(() => _key = v as K),
          child: Column(
            children: [
              for (final o in widget.options)
                RadioListTile<K>(
                  value: o.key,
                  title: Text(o.label),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: true,
              label: Text(widget.ascendingLabel),
              icon: const Icon(Icons.arrow_upward),
            ),
            ButtonSegment(
              value: false,
              label: Text(widget.descendingLabel),
              icon: const Icon(Icons.arrow_downward),
            ),
          ],
          selected: {_asc},
          onSelectionChanged: (s) => setState(() => _asc = s.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.saveAsDefaultLabel),
          value: _save,
          onChanged: (v) => setState(() => _save = v),
        ),
        FilledButton(
          onPressed: () => widget.onApply(_key, _asc, _save),
          child: Text(widget.applyLabel),
        ),
      ],
    );
  }
}

class FilterChipOption {
  const FilterChipOption({required this.id, required this.label});
  final String id;
  final String label;
}

class FilterSection {
  const FilterSection({
    required this.id,
    required this.label,
    required this.chips,
    this.multiSelect = false,
  });
  final String id;
  final String label;
  final List<FilterChipOption> chips;
  final bool multiSelect;
}

/// Section id to the chosen chip ids.
typedef FilterSelection = Map<String, Set<String>>;

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    required this.title,
    required this.sections,
    required this.initial,
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
  final FilterSelection initial;
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
  late final FilterSelection _sel = {
    for (final e in widget.initial.entries) e.key: {...e.value},
  };
  bool _save = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.lg,
      ),
      children: [
        for (final section in widget.sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
            child: Text(section.label, style: theme.textTheme.titleSmall),
          ),
          Wrap(
            spacing: ConsolarrSpacing.sm,
            children: [
              for (final chip in section.chips)
                FilterChip(
                  label: Text(chip.label),
                  selected: _sel[section.id]?.contains(chip.id) ?? false,
                  onSelected: (on) => setState(() {
                    final set = _sel.putIfAbsent(section.id, () => {});
                    if (!section.multiSelect) set.clear();
                    on ? set.add(chip.id) : set.remove(chip.id);
                  }),
                ),
            ],
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.saveAsDefaultLabel),
          value: _save,
          onChanged: (v) => setState(() => _save = v),
        ),
        Row(
          children: [
            TextButton(
              onPressed:
                  widget.activeCount == 0 && _sel.values.every((s) => s.isEmpty)
                  ? null
                  : () {
                      setState(_sel.clear);
                      widget.onClear();
                    },
              child: Text(widget.clearAllLabel),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => widget.onApply(_sel, _save),
              child: Text(widget.applyLabel),
            ),
          ],
        ),
      ],
    );
  }
}
