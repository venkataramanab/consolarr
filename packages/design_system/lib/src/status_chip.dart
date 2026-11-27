// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:material_ui/material_ui.dart';

enum StatusTone { success, warning, error, info, neutral }

/// Compact pill: icon and text always, tone only as a soft extra.
///
/// With [details] the chip is tappable and expands to show them below.
class StatusChip extends StatefulWidget {
  const StatusChip({
    required this.label,
    required this.icon,
    this.tone = StatusTone.neutral,
    this.details,
    this.initiallyExpanded = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final StatusTone tone;
  final String? details;
  final bool initiallyExpanded;

  @override
  State<StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<StatusChip> {
  late bool _expanded = widget.initiallyExpanded;

  Color _toneColor(BuildContext context) {
    final roles = context.roles;
    return switch (widget.tone) {
      StatusTone.success => roles.success,
      StatusTone.warning => roles.warning,
      StatusTone.error => roles.error,
      StatusTone.info => roles.accent,
      StatusTone.neutral => roles.textTertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final tone = _toneColor(context);
    final expandable = widget.details != null;
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: roles.raised,
        borderRadius: ConsolarrRadii.chip,
        border: Border.all(color: tone),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ConsolarrSpacing.md,
          vertical: ConsolarrSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Icon(widget.icon, size: 16, color: tone)),
            const SizedBox(width: ConsolarrSpacing.xs),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
    if (!expandable) {
      return Semantics(
        label: widget.label,
        excludeSemantics: true,
        child: pill,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: widget.label,
          excludeSemantics: true,
          onTap: () => setState(() => _expanded = !_expanded),
          child: InkWell(
            borderRadius: ConsolarrRadii.chip,
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: TouchTargets.of(context).minimum,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: pill,
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ConsolarrSpacing.sm,
            ),
            child: Text(widget.details!, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}
