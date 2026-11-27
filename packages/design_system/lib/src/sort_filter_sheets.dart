// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/settings_rows.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:material_ui/material_ui.dart';

/// One way to sort a list: a [key] the feature understands and its [label].
@immutable
class SortOption<K> {
  const SortOption({required this.key, required this.label});

  final K key;
  final String label;
}

/// Content of a sort sheet: the options (one selected), the direction and an
/// explicit "save as default" switch (defaults are saved only on request).
/// Put it in [showGlassSheet] (the sheet supplies the title bar; [title]
/// names the group for screen readers and is shown when [showTitle]).
///
/// ```dart
/// showGlassSheet<void>(
///   context: context,
///   title: l10n.sortTitle,
///   closeLabel: l10n.commonClose,
///   builder: (context) => SortSheet<MySort>(
///     title: l10n.sortTitle,
///     options: [SortOption(key: MySort.title, label: l10n.sortByTitle)],
///     selected: current,
///     ascending: true,
///     ascendingLabel: l10n.ascending,
///     descendingLabel: l10n.descending,
///     saveAsDefaultLabel: l10n.saveAsDefault,
///     applyLabel: l10n.apply,
///     onApply: (key, ascending, saveAsDefault) { /* ... */ },
///   ),
/// );
/// ```
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
    this.showTitle = false,
    this.saveAsDefault = false,
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

  /// Show [title] as a heading inside the content.
  final bool showTitle;

  /// Initial state of the "save as default" switch.
  final bool saveAsDefault;

  @override
  State<SortSheet<K>> createState() => _SortSheetState<K>();
}

class _SortSheetState<K> extends State<SortSheet<K>> {
  late K _key = widget.selected;
  late bool _ascending = widget.ascending;
  late bool _save = widget.saveAsDefault;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final touch = TouchTargets.of(context).minimum;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle)
            Semantics(
              header: true,
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
          for (final o in widget.options)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: o.key == _key,
              button: true,
              label: o.label,
              excludeSemantics: true,
              onTap: () => setState(() => _key = o.key),
              child: InkWell(
                onTap: () => setState(() => _key = o.key),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: touch),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(o.label, style: theme.textTheme.bodyLarge),
                      ),
                      const SizedBox(width: ConsolarrSpacing.md),
                      Icon(
                        o.key == _key
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: o.key == _key
                            ? roles.accent
                            : roles.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: ConsolarrSpacing.md),
          SegmentedButton<bool>(
            showSelectedIcon: true,
            style: SegmentedButton.styleFrom(minimumSize: Size(0, touch)),
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
          const SizedBox(height: ConsolarrSpacing.sm),
          SwitchRow(
            title: widget.saveAsDefaultLabel,
            value: _save,
            onChanged: (v) => setState(() => _save = v),
          ),
          const SizedBox(height: ConsolarrSpacing.md),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
            onPressed: () => widget.onApply(_key, _ascending, _save),
            child: Text(widget.applyLabel),
          ),
        ],
      ),
    );
  }
}

/// One selectable value of a [FilterSection].
@immutable
class FilterChoice {
  const FilterChoice({required this.id, required this.label});

  final String id;
  final String label;
}

/// A group of chips: pick one ([multiSelect] false) or several.
@immutable
class FilterSection {
  const FilterSection({
    required this.id,
    required this.label,
    required this.chips,
    this.multiSelect = true,
  });

  final String id;
  final String label;
  final List<FilterChoice> chips;
  final bool multiSelect;
}

/// The chosen chip ids per section id. Immutable.
@immutable
class FilterSelection {
  const FilterSelection([this._byId = const {}]);

  final Map<String, Set<String>> _byId;

  /// No filter.
  static const FilterSelection empty = FilterSelection();

  /// The chips chosen in [sectionId].
  Set<String> of(String sectionId) => _byId[sectionId] ?? const {};

  /// Chips chosen across all sections: the "active filters" count.
  int get count => _byId.values.fold(0, (n, s) => n + s.length);

  bool get isEmpty => count == 0;

  /// A copy with [chipId] of [section] toggled (single-select sections
  /// replace their choice).
  FilterSelection toggled(FilterSection section, String chipId) {
    final current = {...of(section.id)};
    if (current.contains(chipId)) {
      current.remove(chipId);
    } else if (section.multiSelect) {
      current.add(chipId);
    } else {
      current
        ..clear()
        ..add(chipId);
    }
    return FilterSelection({
      for (final e in _byId.entries)
        if (e.key != section.id) e.key: e.value,
      if (current.isNotEmpty) section.id: current,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is FilterSelection &&
      other._byId.length == _byId.length &&
      _byId.entries.every((e) {
        final o = other._byId[e.key];
        return o != null &&
            o.length == e.value.length &&
            o.containsAll(e.value);
      });

  @override
  int get hashCode => Object.hashAllUnordered(
    _byId.entries.map(
      (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
    ),
  );
}

/// Content of a filter sheet: sections of chips, the active-filter count,
/// "clear all", an explicit "save as default" switch and Apply. Put it in
/// [showGlassSheet].
///
/// [activeCount] is the number of filters currently applied to the list
/// (shown beside the title and spoken as [activeCountLabel]); [selection] is
/// the initial chip state. The sheet edits a draft; nothing changes until
/// [onApply]. "Clear all" empties the draft and calls [onClear].
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
    this.selection = FilterSelection.empty,
    this.activeCountLabel,
    this.saveAsDefault = false,
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

  /// The applied selection the draft starts from.
  final FilterSelection selection;

  /// Localized, plural-aware text for [activeCount] ("3 filters active");
  /// defaults to the bare number.
  final String? activeCountLabel;
  final bool saveAsDefault;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late FilterSelection _draft = widget.selection;
  late bool _save = widget.saveAsDefault;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final touch = TouchTargets.of(context).minimum;
    final countText = widget.activeCountLabel ?? '${widget.activeCount}';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: countText,
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      if (widget.activeCount > 0)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: roles.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ConsolarrSpacing.sm,
                              vertical: ConsolarrSpacing.xxs,
                            ),
                            child: Text(
                              '${widget.activeCount}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: roles.onAccent,
                              ),
                            ),
                          ),
                        ),
                      if (widget.activeCount > 0 &&
                          widget.activeCountLabel != null) ...[
                        const SizedBox(width: ConsolarrSpacing.sm),
                        Flexible(
                          child: Text(
                            widget.activeCountLabel!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: Size(touch, touch)),
                onPressed: () {
                  setState(() => _draft = FilterSelection.empty);
                  widget.onClear();
                },
                child: Text(widget.clearAllLabel),
              ),
            ],
          ),
          for (final section in widget.sections) ...[
            const SizedBox(height: ConsolarrSpacing.md),
            Semantics(
              header: true,
              child: Text(section.label, style: theme.textTheme.labelLarge),
            ),
            const SizedBox(height: ConsolarrSpacing.sm),
            Wrap(
              spacing: ConsolarrSpacing.sm,
              runSpacing: ConsolarrSpacing.sm,
              children: [
                for (final chip in section.chips)
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: touch),
                    child: FilterChip(
                      label: Text(chip.label),
                      selected: _draft.of(section.id).contains(chip.id),
                      showCheckmark: true,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(
                        () => _draft = _draft.toggled(section, chip.id),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: ConsolarrSpacing.md),
          SwitchRow(
            title: widget.saveAsDefaultLabel,
            value: _save,
            onChanged: (v) => setState(() => _save = v),
          ),
          const SizedBox(height: ConsolarrSpacing.md),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(0, touch)),
            onPressed: () => widget.onApply(_draft, _save),
            child: Text(widget.applyLabel),
          ),
        ],
      ),
    );
  }
}
