// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:consolarr/features/torrents/presentation/speed_header.dart';
import 'package:consolarr/features/torrents/presentation/torrent_row.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The torrent list (TOR-01..TOR-03). Route: `AppRoutes.torrents`.
///
/// Polls while it is the visible tab and the app is resumed; pull to refresh
/// keeps the current content. Sort, filter, search and status tabs come later;
/// the top bar has room for their actions.
class TorrentListScreen extends ConsumerStatefulWidget {
  const TorrentListScreen({this.onAddServer, this.onSpeedHeaderTap, super.key});

  /// Opens server setup from the "no torrent client" state.
  final VoidCallback? onAddServer;

  /// Hook for the speed-limits sheet (not built yet).
  final VoidCallback? onSpeedHeaderTap;

  @override
  ConsumerState<TorrentListScreen> createState() => _TorrentListScreenState();
}

class _TorrentListScreenState extends ConsumerState<TorrentListScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(ref.read(torrentPollIntervalProvider), (_) {
      // Skip while backgrounded or when this tab is not the visible one.
      if (!mounted || !_resumed || !TickerMode.valuesOf(context).enabled)
        return;
      unawaited(ref.read(torrentListProvider.notifier).refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) unawaited(ref.read(torrentListProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() => ref.read(torrentListProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(torrentListProvider);
    return FloatingTopBarScaffold(
      title: l10n.torrentsTitle,
      bodyBuilder: (context, padding) {
        // Order matters: Riverpod keeps the previous value through a reload
        // and through an error, so `value` alone would show the previous
        // server's torrents as current after a switch.
        if (async.isLoading) return _skeleton(padding);
        if (async.hasError) return _error(context, padding, async.error!);
        return switch (async.value) {
          null => _skeleton(padding),
          TorrentsNoServer() => _noServer(context, padding),
          final TorrentsData data => _content(context, padding, data),
        };
      },
    );
  }

  Widget _offlineBanner(AppLocalizations l10n, TorrentsData data) {
    final fetched = data.fetchedAt;
    String? age;
    if (fetched != null) {
      final d = ref.read(clockProvider)().difference(fetched);
      age = d.inSeconds < 5
          ? l10n.torOfflineJustNow
          : l10n.torOfflineAge(formatDuration(l10n, d));
    }
    return OfflineBanner(
      message: l10n.torOfflineMessage,
      ageText: age,
      retryLabel: l10n.torReconnect,
      onRetry: _refresh,
    );
  }

  Widget _skeleton(EdgeInsets padding) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        const SkeletonBox(height: 120),
        for (var i = 0; i < 8; i++) ...const [
          SizedBox(height: ConsolarrSpacing.sm),
          SkeletonBox(height: 72),
        ],
      ],
    );
  }

  Widget _error(BuildContext context, EdgeInsets padding, Object error) {
    final l10n = context.l10n;
    final appError = appErrorOrUnknown(error);
    final text = connectionErrorMessage(l10n, appError);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ErrorState(
          headline: l10n.torErrorHeadline,
          message: text.message,
          hint: text.hint,
          retryLabel: l10n.torRetry,
          onRetry: _refresh,
        ),
      ),
    );
  }

  Widget _noServer(BuildContext context, EdgeInsets padding) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: EmptyState(
        icon: Icons.download_for_offline_outlined,
        headline: l10n.torNoServerHeadline,
        message: l10n.torNoServerMessage,
        actionLabel: widget.onAddServer == null ? null : l10n.torNoServerAction,
        onAction: widget.onAddServer,
      ),
    );
  }

  Widget _header(TorrentsData data) {
    return SpeedHeader(
      down: data.transfer?.dlSpeed,
      up: data.transfer?.upSpeed,
      history: ref.watch(speedHistoryProvider),
      torrentCount: data.torrents.length,
      offline: data.offline,
      partial: data.transferUnavailable,
      onTap: widget.onSpeedHeaderTap,
    );
  }

  Widget _content(BuildContext context, EdgeInsets padding, TorrentsData data) {
    final l10n = context.l10n;
    final side = EdgeInsets.symmetric(horizontal: padding.horizontal / 2);
    final dim = data.offline ? 0.55 : 1.0;
    if (data.torrents.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: Column(
          children: [
            if (data.offline)
              Padding(
                padding: side.copyWith(bottom: ConsolarrSpacing.sm),
                child: _offlineBanner(l10n, data),
              ),
            Padding(padding: side, child: _header(data)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: EmptyState(
                  icon: Icons.download_outlined,
                  headline: l10n.torEmptyHeadline,
                  message: l10n.torEmptyMessage,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      edgeOffset: padding.top,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: padding.top).add(side),
            sliver: SliverToBoxAdapter(
              // The banner scrolls with the content (it must not overlap the
              // speed header the way a floating one would).
              child: Column(
                children: [
                  if (data.offline) ...[
                    _offlineBanner(l10n, data),
                    const SizedBox(height: ConsolarrSpacing.sm),
                  ],
                  _header(data),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(
              top: ConsolarrSpacing.sm,
              bottom: padding.bottom,
            ).add(side),
            sliver: SliverOpacity(
              opacity: dim,
              sliver: SliverList.separated(
                itemCount: data.torrents.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ConsolarrSpacing.sm),
                itemBuilder: (context, i) {
                  final t = data.torrents[i];
                  return TorrentRow(key: ValueKey(t.hash), torrent: t);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
