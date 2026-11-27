// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/group_header_row.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/wanted_providers.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_episode_row.dart';
import 'package:consolarr/features/sonarr/presentation/search/episode_search_control.dart';
import 'package:consolarr/features/sonarr/presentation/search/interactive_search_sheet.dart';
import 'package:consolarr/features/sonarr/presentation/series_views.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_error_view.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_header.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the manual (interactive) release search for an episode. Replaceable
/// in tests.
typedef ManualSearchOpener = void Function(
  BuildContext context,
  SonarrEpisode episode,
  String title,
);

void _defaultManualSearch(
  BuildContext context,
  SonarrEpisode episode,
  String title,
) => showInteractiveSearch(
  context: context,
  target: InteractiveSearchTarget.episode(episode.id),
  title: title,
);

/// The missing tab body (SON-20): scope selector, series filter, search-all,
/// and the episodes grouped by series.
class WantedBody extends ConsumerWidget {
  const WantedBody({
    required this.padding,
    this.onOpenServers,
    this.onManualSearch = _defaultManualSearch,
    super.key,
  });

  final EdgeInsets padding;
  final void Function(BuildContext context)? onOpenServers;
  final ManualSearchOpener onManualSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final wanted = ref.watch(wantedProvider);
    Future<void> refresh() => ref.read(wantedProvider.notifier).refresh();

    Widget pane(Widget child) => RefreshIndicator(
      edgeOffset: padding.top,
      onRefresh: refresh,
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: child,
      ),
    );

    // Order matters: the previous server's value survives reloads/errors.
    if (wanted.isLoading) {
      return _Skeleton(padding: padding, label: l10n.sonarrWantedLoading);
    }
    if (wanted.hasError) {
      return pane(
        SonarrErrorView.unexpected(
          title: l10n.sonarrWantedErrorTitle,
          onRetry: refresh,
        ),
      );
    }
    final state = wanted.value;
    return switch (state) {
      null => _Skeleton(padding: padding, label: l10n.sonarrWantedLoading),
      WantedNoServer() => pane(
        SonarrErrorView.noServer(
          onOpenServers: () => onOpenServers?.call(context),
        ),
      ),
      WantedFailure(:final error) => pane(
        // Keep the scope selector usable so another scope can be tried.
        Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.gutter,
              ),
              child: WantedScopeSelector(),
            ),
            Expanded(
              child: SonarrErrorView(
                title: l10n.sonarrWantedErrorTitle,
                error: error,
                onRetry: refresh,
                onOpenServers: onOpenServers == null
                    ? null
                    : () => onOpenServers!(context),
              ),
            ),
          ],
        ),
      ),
      WantedData() => RefreshIndicator(
        edgeOffset: padding.top,
        onRefresh: refresh,
        child: _List(
          data: state,
          padding: padding,
          onManualSearch: onManualSearch,
        ),
      ),
    };
  }
}

class _List extends ConsumerStatefulWidget {
  const _List({
    required this.data,
    required this.padding,
    required this.onManualSearch,
  });

  final WantedData data;
  final EdgeInsets padding;
  final ManualSearchOpener onManualSearch;

  @override
  ConsumerState<_List> createState() => _ListState();
}

class _ListState extends ConsumerState<_List> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = widget.data;
    final padding = widget.padding;
    final now = ref.watch(clockProvider)();
    final source = ref.watch(artworkSourceProvider);
    final filter = ref.watch(wantedFilterProvider).trim().toLowerCase();
    final allGroups = groupBySeries(data.episodes);
    final groups = filter.isEmpty
        ? allGroups
        : [
            for (final g in allGroups)
              if ((g.series?.title ?? '').toLowerCase().contains(filter)) g,
          ];
    final inset = EdgeInsets.only(left: padding.left, right: padding.right);
    final upcoming = data.scope == WantedScope.upcoming;
    final writable = !data.isOffline;

    // Flatten: a header per series and, when expanded, its episodes.
    final items = <Object>[
      for (final g in groups) ...[
        g,
        if (_expanded.contains(g.seriesId)) ...g.episodes,
      ],
    ];

    final slivers = <Widget>[
      SliverToBoxAdapter(child: SizedBox(height: padding.top)),
      if (data.isOffline)
        SliverPadding(
          padding: inset.copyWith(bottom: ConsolarrSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: OfflineBanner(
              message:
                  '${l10n.sonarrWantedOfflineMessage} '
                  '${l10n.sonarrWantedOfflineWrites}',
              retryLabel: l10n.sonarrRetry,
              onRetry: () => ref.read(wantedProvider.notifier).refresh(),
            ),
          ),
        ),
      SliverPadding(
        padding: inset.copyWith(bottom: ConsolarrSpacing.sm),
        sliver: SliverToBoxAdapter(
          child: WantedHeader(
            showSearchAll: !upcoming,
            searchAllEnabled: writable && data.episodes.isNotEmpty,
          ),
        ),
      ),
    ];

    if (data.episodes.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          child: EmptyState(
            icon: upcoming ? Icons.event_available_outlined : Icons.task_alt,
            headline: upcoming
                ? l10n.sonarrWantedEmptyUpcomingHeadline
                : l10n.sonarrWantedEmptyGoodHeadline,
            message: upcoming
                ? l10n.sonarrWantedEmptyUpcomingMessage
                : l10n.sonarrWantedEmptyGoodMessage,
          ),
        ),
      );
    } else if (groups.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          child: EmptyState(
            icon: Icons.filter_alt_off_outlined,
            headline: l10n.sonarrWantedFilterEmptyHeadline,
            message: l10n.sonarrWantedFilterEmptyMessage,
            actionLabel: l10n.sonarrWantedFilterClear,
            onAction: () => ref.read(wantedFilterProvider.notifier).set(''),
          ),
        ),
      );
    } else {
      slivers.add(
        SliverPadding(
          padding: inset,
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is WantedGroup) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                  child: _GroupHeader(
                    key: ValueKey('g${item.seriesId}'),
                    group: item,
                    source: source,
                    expanded: _expanded.contains(item.seriesId),
                    onToggle: () => setState(() {
                      if (!_expanded.add(item.seriesId)) {
                        _expanded.remove(item.seriesId);
                      }
                    }),
                  ),
                );
              }
              final e = item as SonarrEpisode;
              return Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: ConsolarrSpacing.lg,
                  bottom: ConsolarrSpacing.sm,
                ),
                child: _EpisodeRow(
                  key: ValueKey('e${e.id}'),
                  episode: e,
                  now: now,
                  writable: writable,
                  onManualSearch: widget.onManualSearch,
                ),
              );
            },
          ),
        ),
      );
      if (data.hasMore || data.loadMoreError != null) {
        slivers.add(
          SliverPadding(
            padding: inset.copyWith(top: ConsolarrSpacing.sm),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (data.loadMoreError != null)
                    Text(
                      l10n.sonarrWantedLoadMoreFailed,
                      textAlign: TextAlign.center,
                    ),
                  TextButton(
                    onPressed: data.loadingMore
                        ? null
                        : () => ref.read(wantedProvider.notifier).loadMore(),
                    child: Text(l10n.sonarrWantedLoadMore),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    slivers.add(SliverToBoxAdapter(child: SizedBox(height: padding.bottom)));
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.source,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final WantedGroup group;
  final ArtworkSource? source;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final series = group.series;
    final title = series?.title ?? episodeCode(l10n, group.episodes.first);
    return ArrGroupHeader(
      title: title,
      countText: l10n.sonarrCalendarEpisodeCount(group.episodes.length),
      expanded: expanded,
      onToggle: onToggle,
      semanticsLabel: l10n.sonarrWantedExpandGroup(title),
      leading: series == null
          ? const ArtworkPlaceholder()
          : seriesArtwork(
              source,
              series,
              (32 * MediaQuery.devicePixelRatioOf(context)).round(),
            ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.now,
    required this.writable,
    required this.onManualSearch,
    super.key,
  });

  final SonarrEpisode episode;
  final DateTime now;
  final bool writable;
  final ManualSearchOpener onManualSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final airs = episode.airs?.toLocal();
    final code = episodeCode(l10n, episode);
    final heading = [code, ?episode.title].join(' · ');
    final airText = airs == null
        ? l10n.sonarrWantedNoAirDate
        : (airs.isAfter(now)
              ? l10n.sonarrWantedAirs(airs)
              : l10n.sonarrWantedAired(airs));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.roles.card,
        borderRadius: ConsolarrRadii.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(airText, style: theme.textTheme.bodySmall),
                  const SizedBox(height: ConsolarrSpacing.xs),
                  episodeStatusChip(l10n, episode, now),
                ],
              ),
            ),
            if (writable) ...[
              EpisodeSearchControl(episodeId: episode.id),
              IconButton(
                tooltip: l10n.sonarrWantedManualSearch,
                icon: const Icon(Icons.manage_search),
                onPressed: () => onManualSearch(context, episode, heading),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.padding, required this.label});

  final EdgeInsets padding;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          children: [
            for (var i = 0; i < 8; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: SkeletonBox(
                  height: 64,
                  borderRadius: ConsolarrRadii.card,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
