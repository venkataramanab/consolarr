// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/presentation/detail/detail_hero.dart';
import 'package:consolarr/features/sonarr/presentation/detail/detail_info.dart';
import 'package:consolarr/features/sonarr/presentation/detail/detail_seasons.dart';
import 'package:consolarr/features/sonarr/presentation/detail/edit_series_sheet.dart';
import 'package:consolarr/features/sonarr/presentation/detail/search_confirm.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/screen_tracking.dart';
import 'package:consolarr/features/sonarr/presentation/search/episode_search_control.dart';
import 'package:consolarr/features/sonarr/presentation/search/interactive_search_sheet.dart';
import 'package:consolarr/features/arr_common/presentation/search_status_button.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Series detail (SON-08, SON-09, SON-11, SON-16, SON-17): artwork hero,
/// facts, links and the expandable seasons with their episodes. Child route
/// `/sonarr/series/:id` (NAV-05); a series that no longer exists shows a
/// message instead of an error.
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({required this.seriesId, super.key});

  final int seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = context.roles;
    return TrackScreen(
      screen: ScreenName.sonarrSeriesDetail,
      child: Scaffold(
        backgroundColor: roles.page,
        body: _DetailBody(seriesId: seriesId),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.seriesId});

  final int seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(seriesDetailProvider(seriesId));
    final top = MediaQuery.paddingOf(context).top;
    Future<void> refresh() =>
        ref.read(seriesDetailProvider(seriesId).notifier).refresh();

    // Order matters: Riverpod keeps the previous series through a reload and
    // through an error, so `value` alone could show another server's series.
    Widget content;
    if (async.isLoading) {
      content = DetailSkeleton(topInset: top + ConsolarrSpacing.xxl);
    } else if (async.hasError) {
      final error = async.error;
      final copy = error is AppError
          ? connectionErrorMessage(l10n, error)
          : null;
      content = Padding(
        padding: EdgeInsets.only(top: top + ConsolarrSpacing.xxl),
        child: ErrorState(
          headline: l10n.sonarrErrorTitle,
          message: copy?.message ?? l10n.sonarrErrorGenericMessage,
          hint: copy?.hint ?? l10n.sonarrErrorGenericHint,
          retryLabel: l10n.sonarrRetry,
          onRetry: refresh,
        ),
      );
    } else {
      content = switch (async.value) {
        DetailData() => DetailContent(
          seriesId: seriesId,
          data: async.value! as DetailData,
          topInset: top + ConsolarrSpacing.xxl,
          onRefresh: refresh,
        ),
        DetailGone() => Padding(
          padding: EdgeInsets.only(top: top + ConsolarrSpacing.xxl),
          child: EmptyState(
            icon: Icons.link_off,
            headline: l10n.sonarrDetailGoneHeadline,
            message: l10n.sonarrDetailGoneMessage,
            actionLabel: l10n.sonarrDetailGoneAction,
            onAction: () => _leave(context),
          ),
        ),
        DetailNoServer() || null => Padding(
          padding: EdgeInsets.only(top: top + ConsolarrSpacing.xxl),
          child: EmptyState(
            icon: Icons.dns_outlined,
            headline: l10n.sonarrDetailNoServerHeadline,
            actionLabel: l10n.sonarrDetailGoneAction,
            onAction: () => _leave(context),
          ),
        ),
      };
    }
    final data =
        !async.isLoading && !async.hasError && async.value is DetailData
        ? async.value! as DetailData
        : null;
    return Stack(
      children: [
        Positioned.fill(child: content),
        PositionedDirectional(
          top: top + ConsolarrSpacing.xs,
          start: ConsolarrSpacing.xs,
          end: ConsolarrSpacing.xs,
          child: Row(
            children: [
              const BackButton(),
              const Spacer(),
              if (data != null) _TopActions(seriesId: seriesId, data: data),
            ],
          ),
        ),
      ],
    );
  }

  static void _leave(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
    } else if (router != null) {
      router.go('/sonarr');
    } else {
      Navigator.maybeOf(context)?.maybePop();
    }
  }
}

class _TopActions extends ConsumerWidget {
  const _TopActions({required this.seriesId, required this.data});

  final int seriesId;
  final DetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final writes = !data.isOffline;
    return Row(
      children: [
        IconButton(
          tooltip: writes
              ? l10n.sonarrDetailEdit
              : l10n.sonarrDetailWritesDisabled,
          icon: const Icon(Icons.edit_outlined),
          onPressed: writes
              ? () async {
                  final saved = await showEditSeriesSheet(
                    context: context,
                    seriesId: seriesId,
                  );
                  if (saved == true && context.mounted) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(l10n.sonarrDetailEditSaved)),
                    );
                  }
                }
              : null,
        ),
        PopupMenuButton<int>(
          tooltip: writes
              ? l10n.sonarrDetailMenu
              : l10n.sonarrDetailWritesDisabled,
          enabled: writes,
          icon: const Icon(Icons.more_vert),
          onSelected: (_) async {
            if (await confirmSearch(context, SearchConfirmKind.series) &&
                context.mounted) {
              await ref
                  .read(
                    searchProgressProvider(SearchTarget.series(seriesId))
                        .notifier,
                  )
                  .start();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 0,
              child: Text(l10n.sonarrDetailSearchMissing),
            ),
          ],
        ),
      ],
    );
  }
}

/// The loaded series: hero, info, seasons. Keeps which seasons are expanded.
class DetailContent extends ConsumerStatefulWidget {
  const DetailContent({
    required this.seriesId,
    required this.data,
    required this.topInset,
    required this.onRefresh,
    super.key,
  });

  final int seriesId;
  final DetailData data;
  final double topInset;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends ConsumerState<DetailContent> {
  Set<int>? _expanded;
  List<SonarrEpisode>? _groupedFor;
  Map<int, List<SonarrEpisode>> _grouped = const {};

  Map<int, List<SonarrEpisode>> _group(List<SonarrEpisode> episodes) {
    if (!identical(_groupedFor, episodes)) {
      _groupedFor = episodes;
      _grouped = groupBySeason(episodes);
    }
    return _grouped;
  }

  Future<void> _openLink(Uri uri) async {
    final ok = await ref.read(externalLinkLauncherProvider).open(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.sonarrDetailLinkFailed)),
      );
    }
  }

  void _manual(InteractiveSearchTarget target, String title) {
    showInteractiveSearch(context: context, target: target, title: title);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final data = widget.data;
    final snapshot = data.snapshot;
    final detail = snapshot.detail;
    final now = ref.watch(clockProvider)();
    final media = MediaQuery.paddingOf(context);
    final grouped = _group(snapshot.episodes);
    final seasons = mergedSeasons(detail.seasons, grouped);
    final expanded = _expanded ??= {
      if (seasons.isNotEmpty) seasons.first.number,
    };
    final items = flattenSeasons(seasons, grouped, expanded);
    final lookups = ref.watch(detailLookupsProvider).value;
    final seriesSearch = ref.watch(
      searchProgressProvider(SearchTarget.series(widget.seriesId)),
    );
    final seriesStatus = searchStatusOf(seriesSearch);
    final side = EdgeInsets.symmetric(
      horizontal: ConsolarrSpacing.gutter + media.left,
    );

    return RefreshIndicator(
      edgeOffset: widget.topInset,
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: DetailHero(
              detail: detail,
              artwork: ref.watch(detailArtworkProvider),
              topInset: widget.topInset,
            ),
          ),
          if (data.isOffline)
            SliverPadding(
              padding: side.copyWith(top: ConsolarrSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: OfflineBanner(
                  message: l10n.sonarrDetailOfflineMessage,
                  ageText: l10n.sonarrUpdatedAgo(
                    ageText(l10n, now.difference(snapshot.fetchedAt)),
                  ),
                  retryLabel: l10n.sonarrRetry,
                  onRetry: widget.onRefresh,
                ),
              ),
            ),
          if (seriesStatus != ArrSearchStatus.idle)
            SliverPadding(
              padding: side.copyWith(top: ConsolarrSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ArrSearchButton(
                    status: seriesStatus,
                    labels: searchLabels(l10n),
                    onSearch: () => ref
                        .read(
                          searchProgressProvider(
                            SearchTarget.series(widget.seriesId),
                          ).notifier,
                        )
                        .start(),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: side.copyWith(top: ConsolarrSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: DetailInfo(
                detail: detail,
                lookups: lookups,
                now: now,
                onOpenLink: _openLink,
              ),
            ),
          ),
          SliverPadding(
            padding: side,
            sliver: SliverToBoxAdapter(
              child: DetailHeading(l10n.sonarrDetailSeasons),
            ),
          ),
          if (snapshot.episodesError != null)
            SliverPadding(
              padding: side,
              sliver: SliverToBoxAdapter(
                child: _EpisodesError(
                  error: snapshot.episodesError!,
                  onRetry: () => ref
                      .read(seriesDetailProvider(widget.seriesId).notifier)
                      .reloadEpisodes(),
                ),
              ),
            )
          else if (seasons.isEmpty)
            SliverPadding(
              padding: side,
              sliver: SliverToBoxAdapter(
                child: Text(l10n.sonarrDetailNoEpisodesAtAll),
              ),
            ),
          SliverPadding(
            padding: side.copyWith(bottom: media.bottom + ConsolarrSpacing.xxl),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _item(context, items[index], data, now),
                childCount: items.length,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    SeasonListItem item,
    DetailData data,
    DateTime now,
  ) {
    final l10n = context.l10n;
    return switch (item) {
      SeasonHeaderItem() => SeasonHeaderRow(
        key: ValueKey('season-${item.season.number}'),
        item: item,
        seriesId: widget.seriesId,
        data: data,
        onToggleExpanded: () => setState(() {
          final set = {...?_expanded};
          set.contains(item.season.number)
              ? set.remove(item.season.number)
              : set.add(item.season.number);
          _expanded = set;
        }),
        onSearchSeason: () async {
          if (await confirmSearch(context, SearchConfirmKind.season) &&
              context.mounted) {
            await ref
                .read(
                  searchProgressProvider(
                    SearchTarget.season(
                      seriesId: widget.seriesId,
                      seasonNumber: item.season.number,
                    ),
                  ).notifier,
                )
                .start();
          }
        },
        onSearchManually: () => _manual(
          InteractiveSearchTarget.season(
            seriesId: widget.seriesId,
            seasonNumber: item.season.number,
          ),
          seasonTitle(l10n, item.season.number),
        ),
      ),
      EpisodeItem(:final episode) => EpisodeRow(
        key: ValueKey('episode-${episode.id}'),
        episode: episode,
        data: data,
        now: now,
        onSearchManually: () => _manual(
          InteractiveSearchTarget.episode(episode.id),
          episode.title == null || episode.title!.isEmpty
              ? l10n.sonarrDetailEpisodeUntitled(episode.episodeNumber)
              : l10n.sonarrDetailEpisodeTitle(
                  episode.episodeNumber,
                  episode.title!,
                ),
        ),
      ),
      NoEpisodesItem() => Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.md),
        child: Text(l10n.sonarrDetailNoEpisodes),
      ),
    };
  }
}

class _EpisodesError extends StatelessWidget {
  const _EpisodesError({required this.error, required this.onRetry});

  final AppError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final copy = connectionErrorMessage(l10n, error);
    return ErrorState(
      headline: l10n.sonarrDetailEpisodesErrorTitle,
      message: copy.message,
      hint: copy.hint,
      retryLabel: l10n.sonarrRetry,
      onRetry: onRetry,
    );
  }
}

/// Layout-matching skeleton for the loading state.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({required this.topInset, super.key});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.sonarrDetailLoading,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            SkeletonBox(height: heroBackdropHeight + topInset),
            const SizedBox(height: ConsolarrSpacing.lg),
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ConsolarrSpacing.gutter,
                  vertical: ConsolarrSpacing.xs,
                ),
                child: SkeletonBox(
                  height: 56,
                  borderRadius: ConsolarrRadii.card,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
