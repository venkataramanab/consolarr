// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/arr_common/presentation/search_status_button.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';

/// Localized labels for the search button.
ArrSearchLabels searchLabels(AppLocalizations l10n) => ArrSearchLabels(
  search: l10n.sonarrSearchEpisode,
  searching: l10n.sonarrSearchSearching,
  grabbed: l10n.sonarrSearchGrabbed,
  nothingFound: l10n.sonarrSearchNothingFound,
  failed: l10n.sonarrSearchFailed,
  retry: l10n.sonarrSearchRetry,
);

/// Maps the notifier state to the view-model status.
ArrSearchStatus searchStatusOf(SearchProgress progress) => switch (progress) {
  SearchIdle() => ArrSearchStatus.idle,
  SearchRunning() => ArrSearchStatus.searching,
  SearchGrabbed() => ArrSearchStatus.grabbed,
  SearchNothingFound() || SearchTimedOut() => ArrSearchStatus.nothingFound,
  SearchFailed() => ArrSearchStatus.failed,
};

/// The inline automatic-search control of one episode (SON-16). Disabled with
/// an explanation by passing `enabled: false` (offline).
class EpisodeSearchControl extends ConsumerWidget {
  const EpisodeSearchControl({
    required this.episodeId,
    this.enabled = true,
    super.key,
  });

  final int episodeId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = SearchTarget.episode(episodeId);
    final progress = ref.watch(searchProgressProvider(target));
    final status = searchStatusOf(progress);
    final labels = searchLabels(context.l10n);
    if (!enabled && status == ArrSearchStatus.idle) {
      return const SizedBox.shrink();
    }
    return ArrSearchButton(
      status: status,
      labels: labels,
      onSearch: () => ref.read(searchProgressProvider(target).notifier).start(),
    );
  }
}
