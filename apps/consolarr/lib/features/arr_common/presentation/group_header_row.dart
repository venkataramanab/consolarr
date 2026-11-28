// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Header of an expandable group (a series in a list of episodes): leading
/// artwork, title, count text and an expand/collapse chevron. The whole row
/// is the button; its state is announced as expanded or collapsed.
class ArrGroupHeader extends StatelessWidget {
  const ArrGroupHeader({
    required this.title,
    required this.countText,
    required this.expanded,
    required this.onToggle,
    required this.semanticsLabel,
    this.leading,
    super.key,
  });

  final String title;

  /// Already localized, for example "3 episodes".
  final String countText;
  final bool expanded;
  final VoidCallback onToggle;

  /// Accessible name (plain text), for example "Show episodes of <title>".
  final String semanticsLabel;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = context.roles;
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: joinList(context.l10n, [semanticsLabel, countText]),
      excludeSemantics: true,
      onTap: onToggle,
      child: Material(
        color: roles.card,
        borderRadius: ConsolarrRadii.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ConsolarrSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.md,
                vertical: ConsolarrSpacing.sm,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    SizedBox(width: 32, height: 48, child: leading),
                    const SizedBox(width: ConsolarrSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          countText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: roles.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
