// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// One choice of an [ArrOptionPicker].
class ArrOption<T> {
  const ArrOption(this.value, this.label);

  final T value;
  final String label;
}

/// A labelled single-choice field of an add-options form (quality profile,
/// root folder, series type, monitoring preset). Labels are plain text.
class ArrOptionPicker<T> extends StatelessWidget {
  const ArrOptionPicker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T? value;
  final List<ArrOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
      child: DropdownButtonFormField<T>(
        // Rebuild when the value is changed from outside.
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final o in options)
            DropdownMenuItem<T>(
              value: o.value,
              child: Text(o.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// A labelled on/off option with an optional explanation.
class ArrOptionSwitch extends StatelessWidget {
  const ArrOptionSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    value: value,
    onChanged: onChanged,
  );
}

/// A tag shown by [ArrTagPicker].
class ArrTagOption {
  const ArrTagOption(this.id, this.label);

  final int id;
  final String label;
}

/// Localized strings of [ArrTagPicker].
class ArrTagPickerLabels {
  const ArrTagPickerLabels({
    required this.heading,
    required this.none,
    required this.newTag,
    required this.addTag,
  });

  final String heading;

  /// Shown when there are no tags yet.
  final String none;

  /// Label of the new-tag text field.
  final String newTag;

  /// Tooltip of the button that creates the typed tag.
  final String addTag;
}

/// Multi-select tag chips with inline creation of a new tag (SON-11, SON-19).
class ArrTagPicker extends StatefulWidget {
  const ArrTagPicker({
    required this.tags,
    required this.selected,
    required this.labels,
    required this.onToggle,
    required this.onCreate,
    super.key,
  });

  final List<ArrTagOption> tags;
  final Set<int> selected;
  final ArrTagPickerLabels labels;
  final ValueChanged<int> onToggle;

  /// Creates a tag; returns an error message to show, or null on success.
  final Future<String?> Function(String label) onCreate;

  @override
  State<ArrTagPicker> createState() => _ArrTagPickerState();
}

class _ArrTagPickerState extends State<ArrTagPicker> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final error = await widget.onCreate(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(labels.heading, style: theme.textTheme.labelLarge),
          ),
          const SizedBox(height: ConsolarrSpacing.xs),
          if (widget.tags.isEmpty)
            Text(labels.none, style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: ConsolarrSpacing.sm,
              children: [
                for (final t in widget.tags)
                  FilterChip(
                    label: Text(t.label),
                    selected: widget.selected.contains(t.id),
                    onSelected: (_) => widget.onToggle(t.id),
                  ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: labels.newTag,
                    errorText: _error,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                ),
              ),
              IconButton(
                tooltip: labels.addTag,
                icon: const Icon(Icons.add),
                onPressed: _busy ? null : _create,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
