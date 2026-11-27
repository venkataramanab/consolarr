// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/touch_targets.dart';
import 'package:material_ui/material_ui.dart';

/// List-mode row for a media item: thumbnail, title, dot-separated metadata
/// and trailing badges.
class MediaListTile extends StatelessWidget {
  const MediaListTile({
    required this.title,
    this.metadata = const [],
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.semanticsLabel,
    super.key,
  });

  final String title;

  /// Metadata parts, joined with a middle dot.
  final List<String> metadata;

  /// Usually a [PosterCard]-style thumbnail; sized by the tile.
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String? semanticsLabel;

  static const _dot = ' · ';
  static const double thumbWidth = 48;
  static const double thumbHeight = 72;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final meta = metadata.join(_dot);
    return Semantics(
      container: true,
      button: onTap != null,
      selected: selected,
      label: semanticsLabel ?? (meta.isEmpty ? title : '$title, $meta'),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: selected ? roles.raised : roles.card,
        borderRadius: ConsolarrRadii.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: TouchTargets.of(context).minimum,
            ),
            child: Padding(
              padding: const EdgeInsets.all(ConsolarrSpacing.sm),
              child: Row(
                children: [
                  if (leading != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(ConsolarrRadii.sm),
                      child: SizedBox(
                        width: thumbWidth,
                        height: thumbHeight,
                        child: leading,
                      ),
                    ),
                    const SizedBox(width: ConsolarrSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Flexible(child: trailing!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
