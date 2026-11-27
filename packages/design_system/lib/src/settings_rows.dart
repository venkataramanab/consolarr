// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/glass_sheet.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:material_ui/material_ui.dart';

/// A titled group of settings rows on one card surface.
///
/// ```dart
/// SettingsSection(
///   title: 'Display',
///   children: [
///     SwitchRow(title: 'Larger targets', value: on, onChanged: set),
///     SettingsRow(title: 'About', onTap: openAbout),
///   ],
/// )
/// ```
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    this.footer,
    super.key,
  });

  /// Section heading, announced as a header.
  final String title;
  final List<Widget> children;

  /// Optional explanatory text under the card.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: ConsolarrSpacing.sm,
              bottom: ConsolarrSpacing.sm,
            ),
            child: Semantics(
              header: true,
              container: true,
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: roles.textSecondary,
                ),
              ),
            ),
          ),
          Material(
            color: roles.card,
            borderRadius: ConsolarrRadii.card,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: roles.track),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: ConsolarrSpacing.sm,
                end: ConsolarrSpacing.sm,
                top: ConsolarrSpacing.sm,
              ),
              child: Text(footer!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// A row of [title], optional [subtitle] and leading [icon]; tappable when
/// [onTap] is set (a chevron that mirrors in right-to-left shows then).
/// [value] is shown on the trailing side (the current choice).
///
/// ```dart
/// SettingsRow(
///   title: l10n.about,
///   icon: Icons.info_outline,
///   onTap: () => context.push('/about'),
/// )
/// ```
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.semanticsHint,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// Optional spoken hint ("Opens language choices").
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final active = enabled && onTap != null;
    final foreground = enabled ? roles.textPrimary : roles.textTertiary;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: TouchTargets.of(context).minimum),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ConsolarrSpacing.lg,
          vertical: ConsolarrSpacing.sm,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              ExcludeSemantics(child: Icon(icon, color: roles.textSecondary)),
              const SizedBox(width: ConsolarrSpacing.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: ConsolarrSpacing.sm),
              Flexible(
                child: Text(
                  value!,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: ConsolarrSpacing.sm),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: ConsolarrSpacing.xs),
              ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right,
                  color: roles.textSecondary,
                  textDirection: Directionality.of(context),
                  // Mirrors in right-to-left layouts.
                  applyTextScaling: false,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      enabled: enabled,
      label: [title, ?subtitle, ?value].join(', '),
      hint: semanticsHint,
      excludeSemantics: true,
      onTap: active ? onTap : null,
      child: InkWell(onTap: active ? onTap : null, child: content),
    );
  }
}

/// A [SettingsRow]-shaped on/off switch. The whole row toggles; its state is
/// announced as on/off, not only drawn.
///
/// ```dart
/// SwitchRow(
///   title: l10n.reduceMotion,
///   value: reduced,
///   onChanged: (on) => setReduced(on),
/// )
/// ```
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;

  /// `null` disables the row.
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final active = enabled && onChanged != null;
    return Semantics(
      container: true,
      toggled: value,
      enabled: active,
      label: [title, ?subtitle].join(', '),
      excludeSemantics: true,
      onTap: active ? () => onChanged!(!value) : null,
      child: InkWell(
        onTap: active ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: TouchTargets.of(context).minimum,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ConsolarrSpacing.lg,
              vertical: ConsolarrSpacing.sm,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  ExcludeSemantics(
                    child: Icon(icon, color: roles.textSecondary),
                  ),
                  const SizedBox(width: ConsolarrSpacing.lg),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: active
                              ? roles.textPrimary
                              : roles.textTertiary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: ConsolarrSpacing.md),
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Switch(
                      value: value,
                      onChanged: active ? (_) {} : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One option of a [ChoiceSheetRow].
@immutable
class ChoiceOption<T> {
  const ChoiceOption({required this.value, required this.label, this.hint});

  final T value;
  final String label;

  /// Optional second line (for example a description).
  final String? hint;
}

/// A [SettingsRow] showing the current choice that opens a [showGlassSheet]
/// with the options (a radio list; the selected one carries a check mark and
/// is announced as selected).
///
/// ```dart
/// ChoiceSheetRow<ThemeMode>(
///   title: l10n.theme,
///   closeLabel: l10n.commonClose,
///   options: [ChoiceOption(value: ThemeMode.dark, label: l10n.dark)],
///   selected: mode,
///   onSelected: setMode,
/// )
/// ```
class ChoiceSheetRow<T> extends StatelessWidget {
  const ChoiceSheetRow({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.closeLabel,
    this.icon,
    this.subtitle,
    this.sheetTitle,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String closeLabel;

  /// Heading of the sheet; defaults to [title].
  final String? sheetTitle;
  final bool enabled;

  String get _selectedLabel {
    for (final o in options) {
      if (o.value == selected) return o.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      value: _selectedLabel,
      enabled: enabled,
      onTap: () async {
        final picked = await showGlassSheet<_Picked<T>>(
          context: context,
          title: sheetTitle ?? title,
          closeLabel: closeLabel,
          detents: const GlassSheetDetents(peek: 0.6),
          builder: (context) => _ChoiceList<T>(
            options: options,
            selected: selected,
            onPick: (v) => Navigator.of(context).pop(_Picked(v)),
          ),
        );
        if (picked != null) onSelected(picked.value);
      },
    );
  }
}

class _Picked<T> {
  const _Picked(this.value);
  final T value;
}

class _ChoiceList<T> extends StatelessWidget {
  const _ChoiceList({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  final List<ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final o in options)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: o.value == selected,
            button: true,
            label: [o.label, ?o.hint].join(', '),
            excludeSemantics: true,
            onTap: () => onPick(o.value),
            child: InkWell(
              onTap: () => onPick(o.value),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: TouchTargets.of(context).minimum,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: ConsolarrSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.label, style: theme.textTheme.bodyLarge),
                            if (o.hint != null)
                              Text(o.hint!, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      const SizedBox(width: ConsolarrSpacing.md),
                      Icon(
                        o.value == selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: o.value == selected
                            ? roles.accent
                            : roles.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
