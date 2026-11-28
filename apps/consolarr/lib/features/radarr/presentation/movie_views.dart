// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Widest a poster card grows before another column is added.
const double posterMaxExtent = 160;

/// Height of a group header row.
const double groupHeaderHeight = 40;

/// Poster artwork at display size, or a placeholder.
Widget movieArtwork(ArtworkSource? source, RadarrMovie movie, int cacheWidth) {
  final provider = source?.poster(movie);
  if (provider == null)
    return const ArtworkPlaceholder(icon: Icons.movie_outlined);
  return Image(
    image: ResizeImage(provider, width: cacheWidth),
    fit: BoxFit.cover,
    excludeFromSemantics: true,
    gaplessPlayback: true,
    errorBuilder: (context, error, stack) =>
        const ArtworkPlaceholder(icon: Icons.movie_outlined),
  );
}

/// Downloaded or missing, as icon + text.
Widget fileChip(AppLocalizations l10n, RadarrMovie m) => m.hasFile
    ? StatusChip(
        label: l10n.radarrDownloaded,
        icon: Icons.check_circle_outline,
        tone: StatusTone.success,
      )
    : StatusChip(
        label: l10n.radarrMissing,
        icon: Icons.error_outline,
        tone: StatusTone.warning,
      );

Widget availabilityChip(AppLocalizations l10n, Availability a) {
  final (icon, tone) = availabilityStyle(a);
  return StatusChip(label: availabilityText(l10n, a), icon: icon, tone: tone);
}

/// What a screen reader announces for [m].
String movieSemantics(AppLocalizations l10n, RadarrMovie m, Availability a) {
  final details = joinList(l10n, [
    m.hasFile ? l10n.radarrDownloaded : l10n.radarrMissing,
    m.monitored ? l10n.radarrMonitored : l10n.radarrUnmonitored,
    availabilityText(l10n, a),
    if (m.sizeOnDisk > 0) sizeText(l10n, m.sizeOnDisk),
  ]);
  return l10n.radarrMovieSemantics(m.title, details);
}

/// One poster tile: downloaded/missing, availability, unmonitored; the size
/// and year sit in the subtitle.
class MoviePosterTile extends StatelessWidget {
  const MoviePosterTile({
    required this.movie,
    required this.source,
    required this.now,
    this.onTap,
    super.key,
  });

  final RadarrMovie movie;
  final ArtworkSource? source;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = availabilityOf(movie, now);
    final subtitle = joinParts(l10n, [
      if (movie.year case final year?) l10n.plainInt(year),
      if (movie.sizeOnDisk > 0) sizeText(l10n, movie.sizeOnDisk),
    ]);
    return PosterCard(
      title: movie.title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      semanticsLabel: movieSemantics(l10n, movie, a),
      onTap: onTap,
      imageBuilder: (context, w) => movieArtwork(source, movie, w),
      badges: [
        fileChip(l10n, movie),
        if (!movie.hasFile) availabilityChip(l10n, a),
        if (!movie.monitored)
          StatusChip(
            label: l10n.radarrUnmonitored,
            icon: Icons.bookmark_border,
          ),
      ],
    );
  }
}

class MovieListTile extends StatelessWidget {
  const MovieListTile({
    required this.movie,
    required this.source,
    required this.now,
    this.onTap,
    super.key,
  });

  final RadarrMovie movie;
  final ArtworkSource? source;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final a = availabilityOf(movie, now);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return MediaListTile(
      title: movie.title,
      metadata: [
        if (movie.year case final year?) l10n.plainInt(year),
        availabilityText(l10n, a),
        if (movie.sizeOnDisk > 0) sizeText(l10n, movie.sizeOnDisk),
        movie.monitored ? l10n.radarrMonitored : l10n.radarrUnmonitored,
      ],
      semanticsLabel: movieSemantics(l10n, movie, a),
      onTap: onTap,
      leading: movieArtwork(
        source,
        movie,
        (MediaListTile.thumbWidth * dpr).round(),
      ),
      trailing: fileChip(l10n, movie),
    );
  }
}

/// Row height of list mode, which grows with the text size so rows never
/// clip. Fixed extents make the jump control exact.
double listRowExtent(double textScale) =>
    _listRowBase * textScale.clamp(1.0, 2.2) + ConsolarrSpacing.sm;

/// Two title lines, two metadata lines and the tile padding, at scale 1.0.
const double _listRowBase = 112;

/// Columns of the poster grid for [width] (the same rule as
/// `SliverGridDelegateWithMaxCrossAxisExtent`).
int gridColumns(double width) =>
    (width / (posterMaxExtent + ConsolarrSpacing.sm)).ceil().clamp(1, 12);

/// Height of a poster tile: 2:3 artwork at text scale 1, growing with the
/// text size so the title, year and badges drawn over it never clip.
double gridTileExtent(double tileWidth, double textScale) =>
    tileWidth * 1.5 * (1 + 0.5 * (textScale.clamp(1.0, 3.0) - 1));

/// Where each group starts, for the jump control (RAD-01).
List<double> groupOffsets(
  List<MovieGroup> groups, {
  required bool grid,
  required double width,
  required double textScale,
}) {
  final out = <double>[];
  var offset = 0.0;
  final columns = gridColumns(width);
  const gap = ConsolarrSpacing.sm;
  final tileWidth = (width - (columns - 1) * gap) / columns;
  final rowExtent = grid
      ? gridTileExtent(tileWidth, textScale) + gap
      : listRowExtent(textScale);
  for (final g in groups) {
    out.add(offset);
    final header = g.label.isEmpty ? 0.0 : groupHeaderHeight;
    final rows = grid ? (g.movies.length / columns).ceil() : g.movies.length;
    offset += header + rows * rowExtent;
  }
  return out;
}

/// The library as slivers: a header and a lazily built grid or list per group.
class MovieGroupsSliver extends StatelessWidget {
  const MovieGroupsSliver({
    required this.groups,
    required this.grid,
    required this.source,
    required this.now,
    required this.onOpen,
    super.key,
  });

  final List<MovieGroup> groups;
  final bool grid;
  final ArtworkSource? source;
  final DateTime now;
  final void Function(RadarrMovie movie) onOpen;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extent = listRowExtent(scale);
    if (!grid) return _slivers(extent, null);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = gridColumns(constraints.crossAxisExtent);
        final tileWidth =
            (constraints.crossAxisExtent -
                (columns - 1) * ConsolarrSpacing.sm) /
            columns;
        return _slivers(extent, gridTileExtent(tileWidth, scale));
      },
    );
  }

  Widget _slivers(double extent, double? tileExtent) {
    return SliverMainAxisGroup(
      slivers: [
        for (final g in groups) ...[
          if (g.label.isNotEmpty)
            SliverToBoxAdapter(child: _GroupHeader(label: g.label)),
          if (grid)
            SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: posterMaxExtent,
                mainAxisSpacing: ConsolarrSpacing.sm,
                crossAxisSpacing: ConsolarrSpacing.sm,
                mainAxisExtent: tileExtent,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => MoviePosterTile(
                  key: ValueKey(g.movies[i].id),
                  movie: g.movies[i],
                  source: source,
                  now: now,
                  onTap: () => onOpen(g.movies[i]),
                ),
                childCount: g.movies.length,
                addAutomaticKeepAlives: false,
              ),
            )
          else
            SliverFixedExtentList(
              itemExtent: extent,
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                  child: MovieListTile(
                    key: ValueKey(g.movies[i].id),
                    movie: g.movies[i],
                    source: source,
                    now: now,
                    onTap: () => onOpen(g.movies[i]),
                  ),
                ),
                childCount: g.movies.length,
                addAutomaticKeepAlives: false,
              ),
            ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: groupHeaderHeight,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        header: true,
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
    ),
  );
}

/// Layout-matching skeleton for the loading state.
class MovieSkeleton extends StatelessWidget {
  const MovieSkeleton({required this.mode, required this.padding, super.key});

  final LibraryViewMode mode;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.radarrLoadingLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: mode == LibraryViewMode.grid
                  ? SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: posterMaxExtent,
                            mainAxisSpacing: ConsolarrSpacing.sm,
                            crossAxisSpacing: ConsolarrSpacing.sm,
                            childAspectRatio: 2 / 3,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => const SkeletonBox(
                          borderRadius: ConsolarrRadii.card,
                        ),
                        childCount: 12,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => const Padding(
                          padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                          child: SkeletonBox(
                            height: 88,
                            borderRadius: ConsolarrRadii.card,
                          ),
                        ),
                        childCount: 10,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
