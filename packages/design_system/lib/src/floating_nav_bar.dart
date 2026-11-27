// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/glass_bar.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:material_ui/material_ui.dart';

/// One destination of a [FloatingNavBar].
@immutable
class FloatingNavDestination {
  const FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
    this.semanticsHint,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// Localized label, always visible.
  final String label;

  /// Optional badge drawn on the icon (for example a count or dot).
  final Widget? badge;

  /// Optional localized extra description (for example "2 alerts").
  final String? semanticsHint;
}

/// The floating pill navigation bar. The selected destination is shown by a
/// filled icon, an indicator pill and a bold label (never colour alone) and
/// is announced as selected.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.margin = const EdgeInsets.fromLTRB(
      ConsolarrSpacing.lg,
      0,
      ConsolarrSpacing.lg,
      ConsolarrSpacing.md,
    ),
    super.key,
  });

  final List<FloatingNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Gap to the screen edges; the bar floats detached from them.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: margin,
        child: GlassBar(
          padding: const EdgeInsets.symmetric(
            horizontal: ConsolarrSpacing.xs,
            vertical: ConsolarrSpacing.xs,
          ),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final FloatingNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final color = selected ? roles.textPrimary : roles.textSecondary;
    final icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      color: color,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      hint: destination.semanticsHint,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: ConsolarrRadii.bar,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: TouchTargets.of(context).minimum,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ConsolarrSpacing.xs,
              horizontal: ConsolarrSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: ConsolarrRadii.chip,
                        border: Border.all(
                          color: selected
                              ? roles.accent
                              : const Color(0x00000000),
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ConsolarrSpacing.lg,
                          vertical: ConsolarrSpacing.xxs,
                        ),
                        child: icon,
                      ),
                    ),
                    if (destination.badge != null)
                      PositionedDirectional(
                        end: 0,
                        top: -ConsolarrSpacing.xs,
                        child: destination.badge!,
                      ),
                  ],
                ),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontSize: 14,
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
