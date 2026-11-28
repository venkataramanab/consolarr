// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/queue_row_builder.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/sonarr/application/queue_providers.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/screen_tracking.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Shown in the confirm dialog; a proper noun, not translated.
const _serviceName = 'Sonarr';

/// Body of the queue tab (SON-14): pull to refresh, every state, removal.
///
/// Tells the notifier whether it is on screen so a hidden tab does not poll.
class QueueBody extends ConsumerStatefulWidget {
  const QueueBody({required this.padding, this.onOpenServers, super.key});

  final EdgeInsets padding;
  final VoidCallback? onOpenServers;

  @override
  ConsumerState<QueueBody> createState() => _QueueBodyState();
}

class _QueueBodyState extends ConsumerState<QueueBody> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ref.read(queueProvider.notifier).visible = TickerMode.valuesOf(context)
        .enabled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final queue = ref.watch(queueProvider);
    final padding = widget.padding;
    Future<void> refresh() => ref.read(queueProvider.notifier).refresh();

    Widget withRefresh(Widget child) => RefreshIndicator(
      edgeOffset: padding.top,
      onRefresh: refresh,
      child: child,
    );
    Widget statePane(Widget child) => withRefresh(
      Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: child,
      ),
    );

    // Riverpod keeps the previous server's value through a reload and an
    // error: look at loading and error first.
    if (queue.isLoading) {
      return TrackScreen(
        screen: ScreenName.sonarrQueue,
        child: _Skeleton(padding: padding),
      );
    }
    if (queue.hasError) {
      final error = queue.error;
      return statePane(
        _error(
          l10n,
          error is AppError ? error : const AppError(ErrorCategory.parseError),
          refresh,
        ),
      );
    }
    final state = queue.value;
    return TrackScreen(
      screen: ScreenName.sonarrQueue,
      child: switch (state) {
        null => _Skeleton(padding: padding),
        QueueNoServer() => statePane(
          EmptyState(
            icon: Icons.dns_outlined,
            headline: l10n.sonarrNoServerHeadline,
            message: l10n.sonarrNoServerMessage,
            actionLabel: l10n.sonarrNoServerAction,
            onAction: () {
              final open = widget.onOpenServers;
              if (open != null) {
                open();
              } else {
                GoRouter.maybeOf(context)?.go('/servers');
              }
            },
          ),
        ),
        QueueFailure(:final error) => statePane(_error(l10n, error, refresh)),
        QueueData(:final items) when items.isEmpty && !state.isOffline =>
          statePane(
            EmptyState(
              icon: Icons.download_done_outlined,
              headline: l10n.sonarrQueueEmptyHeadline,
              message: l10n.sonarrQueueEmptyMessage,
              actionLabel: l10n.sonarrRetry,
              onAction: refresh,
            ),
          ),
        QueueData() => withRefresh(_list(context, state, refresh)),
      },
    );
  }

  Widget _error(
    AppLocalizations l10n,
    AppError error,
    Future<void> Function() refresh,
  ) {
    final copy = connectionErrorMessage(l10n, error, kind: ServiceKind.sonarr);
    return ErrorState(
      headline: l10n.sonarrQueueErrorTitle,
      message: copy.message,
      hint: copy.hint,
      retryLabel: l10n.sonarrRetry,
      onRetry: refresh,
    );
  }

  Widget _list(
    BuildContext context,
    QueueData data,
    Future<void> Function() refresh,
  ) {
    final l10n = context.l10n;
    final padding = widget.padding;
    final now = ref.watch(clockProvider)();
    final offline = data.isOffline;
    final items = data.items;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: padding.top)),
        if (offline)
          SliverPadding(
            padding: EdgeInsets.only(
              left: padding.left,
              right: padding.right,
              bottom: ConsolarrSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: OfflineBanner(
                message: l10n.sonarrQueueOfflineMessage,
                ageText: l10n.sonarrUpdatedAgo(
                  ageText(l10n, now.difference(data.fetchedAt)),
                ),
                retryLabel: l10n.sonarrRetry,
                onRetry: refresh,
              ),
            ),
          ),
        SliverPadding(
          padding: padding.copyWith(top: 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: _row(context, items[index], offline: offline),
              ),
              childCount: items.length,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
      ],
    );
  }

  String _label(AppLocalizations l10n, ArrQueueItem item) =>
      item.mediaTitle ?? item.title;

  Widget _row(
    BuildContext context,
    ArrQueueItem item, {
    required bool offline,
  }) {
    final l10n = context.l10n;
    final season = item.seasonNumber;
    final number = item.episodeNumber;
    final code = season != null && number != null
        ? l10n.sonarrQueueEpisodeCode(season, number)
        : null;
    final episode = code == null
        ? null
        : (item.episodeTitle == null
              ? code
              : l10n.sonarrQueueEpisodeLabel(code, item.episodeTitle!));
    final seriesId = item.seriesId;
    return ArrQueueItemRow(
      key: ValueKey(item.id),
      item: item,
      mediaLabel: _label(l10n, item),
      extraDetails: [?episode],
      onOpen: seriesId == null ? null : () => _open(context, seriesId),
      onRemove: offline ? null : () => _remove(context, item),
      removeDisabledReason: offline ? l10n.sonarrQueueRemoveOffline : null,
    );
  }

  void _open(BuildContext context, int seriesId) {
    GoRouter.maybeOf(context)?.push(sonarrSeriesLocation(seriesId));
  }

  Future<void> _remove(BuildContext context, ArrQueueItem item) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final removed = await showArrQueueRemovalDialog(
      context: context,
      itemLabel: _label(l10n, item),
      serviceName: _serviceName,
      kind: ServiceKind.sonarr,
      onConfirm: (choice) =>
          ref.read(queueProvider.notifier).remove(item.id, choice),
    );
    if (removed && mounted) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.sonarrQueueRemoved)));
    }
  }
}

/// Layout-matching skeleton: static (no shimmer needed under reduced motion).
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.sonarrQueueLoadingLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const Padding(
                    padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                    child: SkeletonBox(
                      height: 96,
                      borderRadius: ConsolarrRadii.card,
                    ),
                  ),
                  childCount: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
