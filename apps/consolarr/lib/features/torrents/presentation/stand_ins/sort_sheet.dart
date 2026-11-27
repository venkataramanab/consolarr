// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One sort choice.
class SortOption<K> {
  const SortOption({required this.key, required this.label});

  final K key;
  final String label;
}

/// Sort choices, a direction and "save as default" (stand-in for W4d's
/// `SortSheet`; same parameters).
///
/// TODO(w4d): replace with `SortSheet` from `design_system` after W4d merged.
class SortSheet<K> extends StatefulWidget {
  const SortSheet({
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
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.gutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<K>(
            groupValue: _key,
            onChanged: (v) => setState(() => _key = v ?? _key),
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
          const SizedBox(height: ConsolarrSpacing.sm),
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
            selected: {_ascending},
            onSelectionChanged: (s) => setState(() => _ascending = s.first),
          ),
          CheckboxListTile(
            value: _save,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(widget.saveAsDefaultLabel),
            onChanged: (v) => setState(() => _save = v ?? false),
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
