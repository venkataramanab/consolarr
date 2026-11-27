// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/glass_bar.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:material_ui/material_ui.dart';

/// An action of a [SelectionBar]: an icon button with a tooltip and spoken
/// [label].
@immutable
class SelectionAction {
  const SelectionAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// `null` disables the action.
  final VoidCallback? onPressed;

  /// Error-coloured; the handler must confirm and state consequences.
  final bool destructive;
}

/// The floating bar shown while items are selected (long-press starts the
/// selection; this bar is the visible alternative to every selection
/// gesture): exit, "n selected", select-all and the actions. Frosted glass
/// with a solid fallback (it is a [GlassBar]).
///
/// ```dart
/// SelectionBar(
///   selectedCount: 3,
///   countLabel: l10n.selectedCount(3),
///   exitLabel: l10n.exitSelection,
///   selectAllLabel: l10n.selectAll,
///   onExit: clear,
///   onSelectAll: selectAll,
///   actions: [SelectionAction(icon: Icons.pause, label: 'Pause', onPressed: pause)],
/// )
/// ```
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    required this.selectedCount,
    required this.countLabel,
    required this.exitLabel,
    required this.selectAllLabel,
    required this.onExit,
    required this.onSelectAll,
    required this.actions,
    this.allSelected = false,
    super.key,
  });

  final int selectedCount;

  /// Every item is selected: the select-all button then reports "selected"
  /// to screen readers and is drawn filled (not by colour alone: the icon
  /// changes too).
  final bool allSelected;

  /// Localized, plural-aware ("3 selected").
  final String countLabel;
  final String exitLabel;
  final String selectAllLabel;
  final VoidCallback onExit;
  final VoidCallback onSelectAll;
  final List<SelectionAction> actions;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final touch = TouchTargets.of(context).minimum;
    BoxConstraints box() =>
        BoxConstraints.tightFor(width: touch, height: touch);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: GlassBar(
        padding: const EdgeInsets.symmetric(
          horizontal: ConsolarrSpacing.xs,
          vertical: ConsolarrSpacing.xs,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: exitLabel,
              constraints: box(),
              onPressed: onExit,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  countLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: selectAllLabel,
              constraints: box(),
              isSelected: allSelected,
              onPressed: onSelectAll,
              icon: const Icon(Icons.select_all),
              selectedIcon: const Icon(Icons.deselect),
            ),
            for (final a in actions)
              IconButton(
                tooltip: a.label,
                constraints: box(),
                onPressed: a.onPressed,
                color: a.destructive ? roles.error : null,
                icon: Icon(a.icon),
              ),
          ],
        ),
      ),
    );
  }
}
