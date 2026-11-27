// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/search_status_button.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/search/episode_search_control.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// What an episode row says about the episode.
enum EpisodeStatus { downloaded, downloading, missing, unaired }

/// Derives the episode state: a file wins, then the queue, then the air date.
EpisodeStatus episodeStatus(
  SonarrEpisode episode,
  Set<int> downloading,
  DateTime now,
) {
  if (episode.hasFile) return EpisodeStatus.downloaded;
  if (downloading.contains(episode.id)) return EpisodeStatus.downloading;
  final airs = episode.airs;
  if (airs == null || airs.isAfter(now)) return EpisodeStatus.unaired;
  return EpisodeStatus.missing;
}

String seasonTitle(AppLocalizations l10n, int number) => number == 0
    ? l10n.sonarrDetailSpecials
    : l10n.sonarrDetailSeasonTitle(number);

/// Opens the manual (interactive) search for an episode or a season.
typedef ManualSearchOpener = void Function(SearchTarget target, String title);

/// One entry of the flattened season/episode list.
sealed class SeasonListItem {
  const SeasonListItem();
}

final class SeasonHeaderItem extends SeasonListItem {
  const SeasonHeaderItem(this.season, this.expanded, this.episodes);
  final SonarrSeason season;
  final bool expanded;
  final List<SonarrEpisode> episodes;
}

final class EpisodeItem extends SeasonListItem {
  const EpisodeItem(this.episode);
  final SonarrEpisode episode;
}

final class NoEpisodesItem extends SeasonListItem {
  const NoEpisodesItem(this.season);
  final int season;
}

/// Groups [episodes] by season, ascending by number.
Map<int, List<SonarrEpisode>> groupBySeason(List<SonarrEpisode> episodes) {
  final out = <int, List<SonarrEpisode>>{};
  for (final e in episodes) {
    (out[e.seasonNumber] ??= []).add(e);
  }
  for (final list in out.values) {
    list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
  }
  return out;
}

/// Seasons newest first. Seasons only present in the episode list (not in the
/// series resource) are added so no episode is unreachable.
List<SonarrSeason> mergedSeasons(
  List<SonarrSeason> seasons,
  Map<int, List<SonarrEpisode>> grouped,
) {
  final known = {for (final s in seasons) s.number};
  return [
    ...seasons,
    for (final n in grouped.keys)
      if (!known.contains(n)) SonarrSeason(number: n),
  ]..sort((a, b) => b.number.compareTo(a.number));
}

List<SeasonListItem> flattenSeasons(
  List<SonarrSeason> seasons,
  Map<int, List<SonarrEpisode>> grouped,
  Set<int> expanded,
) => [
  for (final s in seasons) ...[
    SeasonHeaderItem(
      s,
      expanded.contains(s.number),
      grouped[s.number] ?? const [],
    ),
    if (expanded.contains(s.number))
      if ((grouped[s.number] ?? const []).isEmpty)
        NoEpisodesItem(s.number)
      else
        for (final e in grouped[s.number]!) EpisodeItem(e),
  ],
];

/// A season header: expand control, progress in words, the monitor switch and
/// a menu with the search actions. A running season search is shown inline.
class SeasonHeaderRow extends ConsumerWidget {
  const SeasonHeaderRow({
    required this.item,
    required this.seriesId,
    required this.data,
    required this.onToggleExpanded,
    required this.onSearchSeason,
    required this.onSearchManually,
    super.key,
  });

  final SeasonHeaderItem item;
  final int seriesId;
  final DetailData data;
  final VoidCallback onToggleExpanded;
  final VoidCallback onSearchSeason;
  final VoidCallback? onSearchManually;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final number = item.season.number;
    final title = seasonTitle(l10n, number);
    final writes = !data.isOffline;
    final stats = item.season.statistics;
    final progress = stats.totalEpisodeCount > 0
        ? stats.totalEpisodeCount
        : item.episodes.length;
    final files = stats.totalEpisodeCount > 0
        ? stats.episodeFileCount
        : item.episodes.where((e) => e.hasFile).length;
    final search = ref.watch(
      searchProgressProvider(
        SearchTarget.season(seriesId: seriesId, seasonNumber: number),
      ),
    );
    final status = searchStatusOf(search);
    final monitored = item.season.monitored;
    final failed = data.failedSeasons.containsKey(number);
    final pending = data.pendingSeasons.contains(number);
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: roles.card,
          borderRadius: ConsolarrRadii.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              expanded: item.expanded,
              label: item.expanded
                  ? l10n.sonarrDetailHideEpisodes(title)
                  : l10n.sonarrDetailShowEpisodes(title),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: ConsolarrRadii.card,
                onTap: onToggleExpanded,
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
                        Icon(
                          item.expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        const SizedBox(width: ConsolarrSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: theme.textTheme.titleSmall),
                              if (progress > 0)
                                Text(
                                  l10n.sonarrEpisodesProgress(files, progress),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: roles.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: ConsolarrSpacing.md,
                end: ConsolarrSpacing.xs,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MonitorSwitch(
                    label: l10n.sonarrDetailMonitorSeason(title),
                    value: monitored,
                    enabled: writes && !pending,
                    disabledReason: writes
                        ? null
                        : l10n.sonarrDetailWritesDisabled,
                    onChanged: (v) => ref
                        .read(seriesDetailProvider(seriesId).notifier)
                        .setSeasonMonitored(number, monitored: v),
                  ),
                  if (status != ArrSearchStatus.idle)
                    ArrSearchButton(
                      status: status,
                      labels: searchLabels(l10n),
                      onSearch: () => ref
                          .read(
                            searchProgressProvider(
                              SearchTarget.season(
                                seriesId: seriesId,
                                seasonNumber: number,
                              ),
                            ).notifier,
                          )
                          .start(),
                    ),
                  PopupMenuButton<int>(
                    tooltip: writes
                        ? l10n.sonarrDetailMenu
                        : l10n.sonarrDetailWritesDisabled,
                    enabled: writes,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) =>
                        v == 0 ? onSearchSeason() : onSearchManually?.call(),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 0,
                        child: Text(l10n.sonarrDetailSearchSeason),
                      ),
                      if (onSearchManually != null)
                        PopupMenuItem(
                          value: 1,
                          child: Text(l10n.sonarrDetailSearchManually),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (failed)
              _RowFailure(
                onRetry: () => ref
                    .read(seriesDetailProvider(seriesId).notifier)
                    .setSeasonMonitored(
                      number,
                      monitored: data.failedSeasons[number]!,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A monitor switch with an accessible name and, when disabled, a tooltip
/// that says why.
class MonitorSwitch extends StatelessWidget {
  const MonitorSwitch({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.disabledReason,
    super.key,
  });

  final String label;
  final bool value;
  final bool enabled;
  final String? disabledReason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final control = MergeSemantics(
      child: Semantics(
        label: label,
        child: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
    return disabledReason == null
        ? control
        : Tooltip(message: disabledReason, child: control);
  }
}

class _RowFailure extends StatelessWidget {
  const _RowFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: ConsolarrSpacing.md,
        end: ConsolarrSpacing.xs,
      ),
      child: Row(
        children: [
          Flexible(
            child: StatusChip(
              label: l10n.sonarrDetailRowFailed,
              icon: Icons.error_outline,
              tone: StatusTone.warning,
            ),
          ),
          IconButton(
            tooltip: l10n.sonarrRetry,
            icon: const Icon(Icons.refresh),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// One episode: status as icon and text, the monitor switch, the inline
/// automatic search and the manual search.
class EpisodeRow extends ConsumerWidget {
  const EpisodeRow({
    required this.episode,
    required this.data,
    required this.now,
    required this.onSearchManually,
    super.key,
  });

  final SonarrEpisode episode;
  final DetailData data;
  final DateTime now;
  final VoidCallback? onSearchManually;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final status = episodeStatus(episode, data.snapshot.downloading, now);
    final (icon, text, tone) = switch (status) {
      EpisodeStatus.downloaded => (
        Icons.check_circle_outline,
        l10n.sonarrDetailEpisodeDownloaded,
        StatusTone.success,
      ),
      EpisodeStatus.downloading => (
        Icons.downloading,
        l10n.sonarrDetailEpisodeDownloading,
        StatusTone.info,
      ),
      EpisodeStatus.missing => (
        Icons.error_outline,
        l10n.sonarrDetailEpisodeMissing,
        StatusTone.warning,
      ),
      EpisodeStatus.unaired => (
        Icons.schedule,
        l10n.sonarrDetailEpisodeUnaired,
        StatusTone.neutral,
      ),
    };
    final title = episode.title == null || episode.title!.isEmpty
        ? l10n.sonarrDetailEpisodeUntitled(episode.episodeNumber)
        : l10n.sonarrDetailEpisodeTitle(episode.episodeNumber, episode.title!);
    final airs = episode.airs;
    final file = episode.file;
    final details = [
      if (airs != null) l10n.sonarrDetailAirDate(airs.toLocal()),
      if (file != null && file.size > 0) sizeText(l10n, file.size),
      ?file?.qualityName,
    ].join(' · ');
    final writes = !data.isOffline;
    final pending = data.pendingEpisodes.contains(episode.id);
    final failedValue = data.failedEpisodes[episode.id];
    return Padding(
      padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: roles.card,
          borderRadius: ConsolarrRadii.card,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ConsolarrSpacing.md,
            vertical: ConsolarrSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium),
              const SizedBox(height: ConsolarrSpacing.xs),
              StatusChip(label: text, icon: icon, tone: tone),
              if (details.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
                  child: Text(
                    details,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: roles.textSecondary,
                    ),
                  ),
                ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MonitorSwitch(
                    label: l10n.sonarrDetailMonitorEpisode(title),
                    value: episode.monitored,
                    enabled: writes && !pending,
                    disabledReason: writes
                        ? null
                        : l10n.sonarrDetailWritesDisabled,
                    onChanged: (v) => ref
                        .read(
                          seriesDetailProvider(data.snapshot.detail.id)
                              .notifier,
                        )
                        .setEpisodeMonitored(episode.id, monitored: v),
                  ),
                  if (writes)
                    EpisodeSearchControl(episodeId: episode.id)
                  else
                    IconButton(
                      tooltip: l10n.sonarrDetailWritesDisabled,
                      icon: const Icon(Icons.search),
                      onPressed: null,
                    ),
                  if (onSearchManually != null)
                    IconButton(
                      tooltip: writes
                          ? l10n.sonarrDetailSearchManually
                          : l10n.sonarrDetailWritesDisabled,
                      icon: const Icon(Icons.manage_search),
                      onPressed: writes ? onSearchManually : null,
                    ),
                ],
              ),
              if (failedValue != null)
                _RowFailure(
                  onRetry: () => ref
                      .read(
                        seriesDetailProvider(data.snapshot.detail.id).notifier,
                      )
                      .setEpisodeMonitored(episode.id, monitored: failedValue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
