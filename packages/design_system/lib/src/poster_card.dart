// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/label_separators.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:design_system/src/spacing.dart';
import 'package:material_ui/material_ui.dart';

/// Builds the artwork. [cacheWidth] is the display width in physical pixels:
/// pass it to the image decoder so posters are decoded at display size.
typedef ArtworkBuilder = Widget Function(BuildContext context, int cacheWidth);

/// Neutral placeholder for missing or failed artwork. Decorative, hidden from
/// screen readers.
class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({this.icon = Icons.image_outlined, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    return ExcludeSemantics(
      child: ColoredBox(
        color: roles.raised,
        child: Center(child: Icon(icon, color: roles.textTertiary, size: 32)),
      ),
    );
  }
}

/// A poster tile: artwork with a scrim and the title over it, badges on top.
class PosterCard extends StatelessWidget {
  const PosterCard({
    required this.title,
    this.subtitle,
    this.imageBuilder,
    this.badges = const [],
    this.onTap,
    this.onLongPress,
    this.aspectRatio = 2 / 3,
    this.selected = false,
    this.semanticsLabel,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Null shows [ArtworkPlaceholder].
  final ArtworkBuilder? imageBuilder;

  /// Compact badges drawn at the top leading corner (use sparingly).
  final List<Widget> badges;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double aspectRatio;
  final bool selected;

  /// Overrides the default `title, subtitle` announcement.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Semantics(
        container: true,
        button: onTap != null,
        selected: selected,
        label:
            semanticsLabel ??
            ConsolarrSeparators.of(context).joinList([title, subtitle]),
        excludeSemantics: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 160.0;
            final cacheWidth = (width * dpr).round().clamp(1, 4096);
            return ClipRRect(
              borderRadius: ConsolarrRadii.card,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageBuilder?.call(context, cacheWidth) ??
                      const ArtworkPlaceholder(),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [
                            roles.page.withValues(alpha: 0),
                            roles.page.withValues(alpha: 0.94),
                          ],
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: ConsolarrSpacing.sm,
                    end: ConsolarrSpacing.sm,
                    bottom: ConsolarrSpacing.sm,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: roles.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (badges.isNotEmpty)
                    PositionedDirectional(
                      start: ConsolarrSpacing.xs,
                      end: ConsolarrSpacing.xs,
                      top: ConsolarrSpacing.xs,
                      child: Wrap(
                        spacing: ConsolarrSpacing.xs,
                        runSpacing: ConsolarrSpacing.xs,
                        children: badges,
                      ),
                    ),
                  if (selected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: ConsolarrRadii.card,
                        border: Border.all(color: roles.accent, width: 3),
                      ),
                    ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: onTap, onLongPress: onLongPress),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
