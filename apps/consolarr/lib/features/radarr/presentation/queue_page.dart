// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/queue_row_builder.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/poller.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Queue (RAD-11): active downloads with progress in words, status chips and
/// the removal flow. Polls only while [active] and the app is in front.
class QueuePage extends ConsumerWidget {
  const QueuePage({required this.padding, required this.active, super.key});

  final EdgeInsets padding;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(queueProvider);
    Future<void> refresh() => ref.read(queueProvider.notifier).refresh();

    Widget pane(Widget child) => RefreshIndicator(
      onRefresh: refresh,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.maxHeight - padding.vertical,
            ),
            child: child,
          ),
        ),
      ),
    );

    final Widget body;
    if (async.isLoading) {
      body = ListSkeleton(padding: padding);
    } else if (async.hasError || async.value == null) {
      body = pane(
        radarrErrorView(
          context,
          const AppError(ErrorCategory.parseError),
          onRetry: refresh,
        ),
      );
    } else {
      body = switch (async.value!) {
        RadarrNoServer() || RadarrGone() => pane(radarrNoServerView(context)),
        RadarrFailure(:final error) => pane(
          radarrErrorView(context, error, onRetry: refresh),
        ),
        RadarrData(:final value, :final isOffline)
            when value.isEmpty && !isOffline =>
          pane(
            EmptyState(
              icon: Icons.download_done,
              headline: context.l10n.radarrQueueEmptyHeadline,
              message: context.l10n.radarrQueueEmptyMessage,
            ),
          ),
        final RadarrData<List<ArrQueueItem>> data => RefreshIndicator(
          onRefresh: refresh,
          child: _QueueList(data: data, padding: padding, onRetry: refresh),
        ),
      };
    }
    return RadarrScreenView(
      screen: ScreenName.radarrQueue,
      child: VisiblePoller(active: active, onTick: refresh, child: body),
    );
  }
}

/// The queue rows, with the offline banner above them when the list is the
/// cached copy (removing is disabled then).
class _QueueList extends ConsumerWidget {
  const _QueueList({
    required this.data,
    required this.padding,
    required this.onRetry,
  });

  final RadarrData<List<ArrQueueItem>> data;
  final EdgeInsets padding;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final titles = ref.watch(movieTitlesProvider);
    final offline = data.isOffline;
    final items = data.value;
    final now = ref.watch(clockProvider)();

    String label(ArrQueueItem item) =>
        titles[item.movieId] ?? item.mediaTitle ?? item.title;

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
              child: offlineBanner(
                context,
                fetchedAt: data.snapshot.fetchedAt,
                now: now,
                onRetry: onRetry,
              ),
            ),
          ),
        SliverPadding(
          padding: padding.copyWith(top: 0),
          sliver: SliverList.builder(
            itemCount: items.length,
            addAutomaticKeepAlives: false,
            itemBuilder: (context, i) {
              final item = items[i];
              final movieId = item.movieId;
              return Padding(
                padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                child: ArrQueueItemRow(
                  key: ValueKey(item.id),
                  item: item,
                  mediaLabel: label(item),
                  onOpen: movieId == null
                      ? null
                      : () => openMovie(context, movieId),
                  onRemove: offline
                      ? null
                      : () => _remove(context, ref, item, label(item)),
                  removeDisabledReason: offline
                      ? l10n.radarrWritesDisabled
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ArrQueueItem item,
    String itemLabel,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final removed = await showArrQueueRemovalDialog(
      context: context,
      itemLabel: itemLabel,
      // A proper noun, not translated.
      serviceName: 'Radarr',
      onConfirm: (choice) => ref
          .read(queueProvider.notifier)
          .remove(
            item,
            removeFromClient: choice.removeFromClient,
            blocklist: choice.blocklist,
          ),
    );
    if (removed) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.radarrQueueRemoved)));
    }
  }
}
