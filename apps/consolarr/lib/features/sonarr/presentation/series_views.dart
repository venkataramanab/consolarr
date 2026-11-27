// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:design_system/design_system.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Widest a poster card grows before another column is added.
const double posterMaxExtent = 160;

const _dot = ' · ';

/// Opens the detail screen of series [id] (NAV-05 path).
void openSeries(BuildContext context, int id) =>
    GoRouter.maybeOf(context)?.push(sonarrSeriesLocation(id));

/// Poster artwork at display size, or a placeholder when there is none or it
/// fails to load.
Widget seriesArtwork(
  ArtworkSource? source,
  SonarrSeries series,
  int cacheWidth,
) {
  final provider = source?.poster(series);
  if (provider == null) return const ArtworkPlaceholder();
  return Image(
    image: ResizeImage(provider, width: cacheWidth),
    fit: BoxFit.cover,
    excludeFromSemantics: true,
    gaplessPlayback: true,
    errorBuilder: (context, error, stack) => const ArtworkPlaceholder(),
  );
}

(IconData, StatusTone) _statusStyle(SeriesStatus status) => switch (status) {
  SeriesStatus.continuing => (Icons.sync, StatusTone.success),
  SeriesStatus.ended => (Icons.check_circle_outline, StatusTone.neutral),
  SeriesStatus.upcoming => (Icons.schedule, StatusTone.info),
  SeriesStatus.deleted => (Icons.delete_outline, StatusTone.warning),
  SeriesStatus.unknown => (Icons.help_outline, StatusTone.neutral),
};

/// Status badge (icon and text), or null for an unknown status.
Widget? statusChip(AppLocalizations l10n, SeriesStatus status) {
  final text = statusText(l10n, status);
  if (text == null) return null;
  final (icon, tone) = _statusStyle(status);
  return StatusChip(label: text, icon: icon, tone: tone);
}

String _monitoredText(AppLocalizations l10n, SonarrSeries s) =>
    s.monitored ? l10n.sonarrMonitored : l10n.sonarrUnmonitored;

/// What a screen reader announces for [s]: status, monitoring, episodes.
String semanticsLabel(AppLocalizations l10n, SonarrSeries s) {
  final stats = s.statistics;
  final details = [
    ?statusText(l10n, s.status),
    _monitoredText(l10n, s),
    if (stats.totalEpisodeCount > 0)
      l10n.sonarrEpisodesProgress(
        stats.episodeFileCount,
        stats.totalEpisodeCount,
      ),
  ].join(', ');
  return l10n.sonarrSeriesSemantics(s.title, details);
}

/// One poster tile. Badges are sparing: status, and unmonitored only.
class SeriesPosterTile extends StatelessWidget {
  const SeriesPosterTile({
    required this.series,
    required this.source,
    this.now,
    this.onTap,
    super.key,
  });

  final SonarrSeries series;
  final ArtworkSource? source;
  final DateTime? now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stats = series.statistics;
    final next = now == null
        ? null
        : nextAiringText(l10n, series.nextAiring, now!);
    final subtitle = [
      if (series.year != null) '${series.year}',
      if (stats.totalEpisodeCount > 0)
        l10n.sonarrEpisodesShort(
          stats.episodeFileCount,
          stats.totalEpisodeCount,
        ),
      ?next,
    ].join(_dot);
    return PosterCard(
      title: series.title,
      onTap: onTap ?? () => openSeries(context, series.id),
      subtitle: subtitle.isEmpty ? null : subtitle,
      semanticsLabel: semanticsLabel(l10n, series),
      imageBuilder: (context, cacheWidth) =>
          seriesArtwork(source, series, cacheWidth),
      badges: [
        ?statusChip(l10n, series.status),
        if (!series.monitored)
          StatusChip(
            label: l10n.sonarrUnmonitored,
            icon: Icons.bookmark_border,
          ),
      ],
    );
  }
}

/// One list row: thumbnail, title, dot-separated facts and a status badge.
class SeriesListTile extends StatelessWidget {
  const SeriesListTile({
    required this.series,
    required this.source,
    required this.now,
    this.onTap,
    super.key,
  });

  final SonarrSeries series;
  final ArtworkSource? source;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stats = series.statistics;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final next = nextAiringText(l10n, series.nextAiring, now);
    final metadata = [
      if (series.year != null) '${series.year}',
      ?series.network,
      if (stats.seasonCount > 0) l10n.sonarrSeasonCount(stats.seasonCount),
      if (stats.totalEpisodeCount > 0)
        l10n.sonarrEpisodesProgress(
          stats.episodeFileCount,
          stats.totalEpisodeCount,
        ),
      if (stats.sizeOnDisk > 0) sizeText(l10n, stats.sizeOnDisk),
      _monitoredText(l10n, series),
      ?next,
    ];
    return MediaListTile(
      title: series.title,
      onTap: onTap ?? () => openSeries(context, series.id),
      metadata: metadata,
      semanticsLabel: semanticsLabel(l10n, series),
      leading: seriesArtwork(
        source,
        series,
        (MediaListTile.thumbWidth * dpr).round(),
      ),
      trailing: statusChip(l10n, series.status),
    );
  }
}

/// Poster grid as a sliver (adaptive column count, built lazily).
class SeriesGridSliver extends StatelessWidget {
  const SeriesGridSliver({
    required this.series,
    required this.source,
    this.now,
    super.key,
  });

  final List<SonarrSeries> series;
  final ArtworkSource? source;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: posterMaxExtent,
        mainAxisSpacing: ConsolarrSpacing.sm,
        crossAxisSpacing: ConsolarrSpacing.sm,
        childAspectRatio: 2 / 3,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => SeriesPosterTile(
          key: ValueKey(series[index].id),
          series: series[index],
          source: source,
          now: now,
        ),
        childCount: series.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

/// List rows as a sliver, built lazily.
class SeriesListSliver extends StatelessWidget {
  const SeriesListSliver({
    required this.series,
    required this.source,
    required this.now,
    super.key,
  });

  final List<SonarrSeries> series;
  final ArtworkSource? source;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
          child: SeriesListTile(
            key: ValueKey(series[index].id),
            series: series[index],
            source: source,
            now: now,
          ),
        ),
        childCount: series.length,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

/// Layout-matching skeleton for the loading state.
class SeriesSkeleton extends StatelessWidget {
  const SeriesSkeleton({required this.mode, required this.padding, super.key});

  final LibraryViewMode mode;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.sonarrLoadingLabel;
    return Semantics(
      label: label,
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
                        (context, index) => const SkeletonBox(
                          borderRadius: ConsolarrRadii.card,
                        ),
                        childCount: 12,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => const Padding(
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
