// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/presentation/series_views.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Poster width in the hero.
const double heroPosterWidth = 96;

/// Height of the backdrop area.
const double heroBackdropHeight = 280;

/// Artwork-led header (SON-08): fanart backdrop under a scrim, then the
/// poster, title and status chips in the faded zone. Both images are decoded
/// at display size. Decorative imagery is hidden from semantics.
class DetailHero extends StatelessWidget {
  const DetailHero({
    required this.detail,
    required this.artwork,
    required this.topInset,
    super.key,
  });

  final SonarrSeriesDetail detail;
  final DetailArtwork? artwork;

  /// Space for the floating back/edit buttons.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final series = detail.summary;
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final backdrop = artwork?.backdrop(series);
    final poster = artwork?.poster(series);
    final facts = joinParts(l10n, [
      if (series.year case final year?) l10n.plainInt(year),
      ?series.network,
    ]);
    return SizedBox(
      height: heroBackdropHeight + topInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: backdrop == null
                ? ColoredBox(color: roles.raised)
                : Image(
                    image: ResizeImage(backdrop, width: (width * dpr).round()),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) =>
                        ColoredBox(color: roles.raised),
                  ),
          ),
          // Scrim: keeps the text readable and fades into the page colour.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  roles.page.withValues(alpha: 0.35),
                  roles.page.withValues(alpha: 0.7),
                  roles.page,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: ConsolarrSpacing.gutter,
            end: ConsolarrSpacing.gutter,
            bottom: ConsolarrSpacing.md,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: heroPosterWidth,
                    height: heroPosterWidth * 1.5,
                    child: ClipRRect(
                      borderRadius: ConsolarrRadii.card,
                      child: poster == null
                          ? const ArtworkPlaceholder()
                          : Image(
                              image: ResizeImage(
                                poster,
                                width: (heroPosterWidth * dpr).round(),
                              ),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stack) =>
                                  const ArtworkPlaceholder(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: ConsolarrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          series.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      if (facts.isNotEmpty)
                        Text(
                          facts,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: roles.textSecondary,
                          ),
                        ),
                      const SizedBox(height: ConsolarrSpacing.sm),
                      Wrap(
                        spacing: ConsolarrSpacing.xs,
                        runSpacing: ConsolarrSpacing.xs,
                        children: [
                          ?statusChip(l10n, series.status),
                          StatusChip(
                            label: series.monitored
                                ? l10n.sonarrMonitored
                                : l10n.sonarrUnmonitored,
                            icon: series.monitored
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
