// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One sortable key with its localized label.
class SortOption<K> {
  const SortOption({required this.key, required this.label});
  final K key;
  final String label;
}

/// Stand-in with the contract of W4d's `SortSheet<K>`: the content of a sort
/// sheet (key rows, direction, "save as default", apply).
///
/// TODO(w4d): replace with `design_system`'s `SortSheet` once W4d has merged.
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
  late bool _ascending = widget.ascending;
  bool _save = false;

  @override
  Widget build(BuildContext context) {
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
          for (final option in widget.options)
            ListTile(
              key: ValueKey('sort-${option.key}'),
              title: Text(option.label),
              selected: option.key == _key,
              trailing: option.key == _key ? const Icon(Icons.check) : null,
              onTap: () => setState(() => _key = option.key),
            ),
          const SizedBox(height: ConsolarrSpacing.sm),
          Wrap(
            spacing: ConsolarrSpacing.sm,
            children: [
              ChoiceChip(
                label: Text(widget.ascendingLabel),
                avatar: const Icon(Icons.arrow_upward, size: 18),
                selected: _ascending,
                onSelected: (_) => setState(() => _ascending = true),
              ),
              ChoiceChip(
                label: Text(widget.descendingLabel),
                avatar: const Icon(Icons.arrow_downward, size: 18),
                selected: !_ascending,
                onSelected: (_) => setState(() => _ascending = false),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.saveAsDefaultLabel),
            value: _save,
            onChanged: (v) => setState(() => _save = v),
          ),
          FilledButton(
            onPressed: () => widget.onApply(_key, _ascending, _save),
            child: Text(widget.applyLabel),
          ),
        ],
      ),
    );
  }
}
