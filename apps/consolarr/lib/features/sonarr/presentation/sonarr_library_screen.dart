// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/error_messages.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/series_views.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The route the add-server and "check settings" shortcuts open.
const _serversRoute = '/servers';

/// Series library (SON-01): poster grid or list, pull to refresh, and every
/// state: loading, data, empty, no server, error per category (unauthorized,
/// unreachable, unsupported version, ...) and offline with cached data.
///
/// The top bar's `actions` have room for the sort/filter/search controls that
/// follow (SON-02..04).
class SonarrLibraryScreen extends ConsumerWidget {
  const SonarrLibraryScreen({this.onOpenServers, super.key});

  /// Opens the servers screen. Defaults to `go('/servers')`.
  final VoidCallback? onOpenServers;

  void _openServers(BuildContext context) {
    final callback = onOpenServers;
    if (callback != null) {
      callback();
    } else {
      GoRouter.maybeOf(context)?.go(_serversRoute);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mode = ref.watch(viewModeProvider);
    final isGrid = mode == LibraryViewMode.grid;
    return FloatingTopBarScaffold(
      title: l10n.sonarrTitle,
      actions: [
        IconButton(
          tooltip: isGrid
              ? l10n.sonarrSwitchToListTooltip
              : l10n.sonarrSwitchToGridTooltip,
          icon: Icon(isGrid ? Icons.view_list_outlined : Icons.grid_view),
          onPressed: () => ref
              .read(viewModeProvider.notifier)
              .set(isGrid ? LibraryViewMode.list : LibraryViewMode.grid),
        ),
      ],
      bodyBuilder: (context, padding) =>
          _Body(padding: padding, mode: mode, onOpenServers: _openServers),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.padding,
    required this.mode,
    required this.onOpenServers,
  });

  final EdgeInsets padding;
  final LibraryViewMode mode;
  final void Function(BuildContext context) onOpenServers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final library = ref.watch(seriesLibraryProvider);
    Future<void> refresh() =>
        ref.read(seriesLibraryProvider.notifier).refresh();

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

    final state = library.value;
    if (state == null) {
      if (library.hasError) {
        final copy = sonarrUnexpectedErrorCopy(l10n);
        return statePane(
          ErrorState(
            headline: copy.title,
            message: copy.message,
            hint: copy.hint,
            retryLabel: l10n.sonarrRetry,
            onRetry: refresh,
          ),
        );
      }
      return SeriesSkeleton(mode: mode, padding: padding);
    }
    return switch (state) {
      LibraryNoServer() => statePane(
        EmptyState(
          icon: Icons.dns_outlined,
          headline: l10n.sonarrNoServerHeadline,
          message: l10n.sonarrNoServerMessage,
          actionLabel: l10n.sonarrNoServerAction,
          onAction: () => onOpenServers(context),
        ),
      ),
      LibraryFailure(:final error) => statePane(
        _errorState(context, l10n, error, refresh),
      ),
      LibraryData(:final isEmpty) =>
        isEmpty && !state.isOffline
            ? statePane(
                EmptyState(
                  icon: Icons.tv_outlined,
                  headline: l10n.sonarrEmptyHeadline,
                  message: l10n.sonarrEmptyMessage,
                  actionLabel: l10n.sonarrEmptyAction,
                  onAction: refresh,
                ),
              )
            : withRefresh(_content(context, ref, state, padding, refresh)),
    };
  }

  Widget _errorState(
    BuildContext context,
    AppLocalizations l10n,
    AppError error,
    Future<void> Function() refresh,
  ) {
    final copy = sonarrErrorCopy(l10n, error);
    return ErrorState(
      headline: copy.title,
      message: copy.message,
      hint: copy.hint,
      retryLabel: l10n.sonarrRetry,
      onRetry: refresh,
      secondaryLabel: copy.fixedInServerSettings
          ? l10n.sonarrOpenServers
          : null,
      onSecondary: copy.fixedInServerSettings
          ? () => onOpenServers(context)
          : null,
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    LibraryData data,
    EdgeInsets padding,
    Future<void> Function() refresh,
  ) {
    final l10n = context.l10n;
    final source = ref.watch(artworkSourceProvider);
    final now = ref.watch(clockProvider)();
    final snapshot = data.snapshot;
    final listPadding = padding.copyWith(top: 0);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: padding.top)),
        if (data.isOffline)
          SliverPadding(
            padding: EdgeInsets.only(
              left: padding.left,
              right: padding.right,
              bottom: ConsolarrSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: OfflineBanner(
                message: l10n.sonarrOfflineMessage,
                ageText: l10n.sonarrUpdatedAgo(
                  ageText(l10n, now.difference(snapshot.fetchedAt)),
                ),
                retryLabel: l10n.sonarrRetry,
                onRetry: refresh,
              ),
            ),
          ),
        SliverPadding(
          padding: listPadding,
          sliver: mode == LibraryViewMode.grid
              ? SeriesGridSliver(series: snapshot.series, source: source)
              : SeriesListSliver(
                  series: snapshot.series,
                  source: source,
                  now: now,
                ),
        ),
      ],
    );
  }
}
