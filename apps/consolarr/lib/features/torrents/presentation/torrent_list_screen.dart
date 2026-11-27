// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/features/torrents/application/poll_scheduler.dart';
import 'package:consolarr/features/torrents/application/torrent_actions_controller.dart';
import 'package:consolarr/features/torrents/application/torrent_view.dart';
import 'package:consolarr/features/torrents/application/torrent_view_provider.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:consolarr/features/torrents/presentation/error_text.dart';
import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:consolarr/features/torrents/presentation/host_picker.dart';
import 'package:consolarr/features/torrents/presentation/poll_dialog.dart';
import 'package:consolarr/features/torrents/presentation/remove_dialog.dart';
import 'package:consolarr/features/torrents/presentation/speed_header.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:consolarr/features/torrents/presentation/stand_ins/glass_sheet.dart';
import 'package:consolarr/features/torrents/presentation/stand_ins/sort_sheet.dart';
import 'package:consolarr/features/torrents/presentation/status_tabs.dart';
import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_row.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:torrent_clients/torrent_clients.dart';

enum _MenuAction { search, sort, pauseAll, resumeAll, interval }

/// The torrent list (TOR-01..TOR-03, TOR-06, TOR-18).
///
/// Polls while it is the visible tab and the app is resumed, backing off when
/// the server keeps failing; pull to refresh keeps the current content.
class TorrentListScreen extends ConsumerStatefulWidget {
  const TorrentListScreen({this.onAddServer, this.onSpeedHeaderTap, super.key});

  /// Opens server setup from the "no torrent client" state.
  final VoidCallback? onAddServer;

  /// Overrides what a tap on the speed header does (default: the limits sheet).
  final VoidCallback? onSpeedHeaderTap;

  @override
  ConsumerState<TorrentListScreen> createState() => _TorrentListScreenState();
}

class _TorrentListScreenState extends ConsumerState<TorrentListScreen>
    with WidgetsBindingObserver {
  late final PollScheduler _scheduler;
  bool _resumed = true;
  bool _searching = false;

  /// The row widgets built last time. A row whose data did not change gets
  /// the very same instance back, so Flutter skips its subtree entirely.
  final Map<String, _RowEntry> _rows = {};
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduler = PollScheduler(
      interval: ref.read(torrentPollIntervalProvider),
      // Skip while backgrounded or when this tab is not the visible one.
      isVisible: () =>
          mounted && _resumed && TickerMode.valuesOf(context).enabled,
      tick: () => ref.read(torrentListProvider.notifier).refresh(quiet: true),
    )..start();
    ref.listenManual(
      torrentPollIntervalProvider,
      (_, next) => _scheduler.setInterval(next),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) unawaited(_scheduler.pollNow());
  }

  @override
  void dispose() {
    _scheduler.dispose();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    await ref.read(torrentListProvider.notifier).refresh();
  }

  void _toast(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _bulk({
    required bool pause,
    required List<String> hashes,
  }) async {
    final l10n = context.l10n;
    final ok = await confirmDialog(
      context,
      title: pause ? l10n.torPauseAllTitle : l10n.torResumeAllTitle,
      body: pause
          ? l10n.torPauseAllBody(hashes.length)
          : l10n.torResumeAllBody(hashes.length),
      confirmLabel: pause ? l10n.torPauseAllConfirm : l10n.torResumeAllConfirm,
    );
    if (!ok || !mounted) return;
    final actions = ref.read(torrentActionsProvider.notifier);
    final r = await (pause
        ? actions.pauseAll(hashes)
        : actions.resumeAll(hashes));
    if (!mounted) return;
    final error = r.errorOrNull;
    if (error != null) {
      _toast(l10n.torActionFailed(torrentErrorReason(l10n, error)));
    }
  }

  Future<void> _rowAction(Torrent t, _RowAction action) async {
    final l10n = context.l10n;
    final actions = ref.read(torrentActionsProvider.notifier);
    Result<void>? r;
    switch (action) {
      case _RowAction.pause:
        r = await actions.pause(t.hash);
      case _RowAction.resume:
        r = await actions.resume(t.hash);
      case _RowAction.remove:
        final choice = await showRemoveDialog(context, t.name);
        if (choice == null || !mounted) return;
        r = await actions.remove(t.hash, deleteFiles: choice.deleteFiles);
    }
    if (!mounted) return;
    final error = r.errorOrNull;
    if (error != null) {
      _toast(l10n.torActionFailed(torrentErrorReason(l10n, error)));
    }
  }

  void _rowMenu(Torrent t) {
    final l10n = context.l10n;
    final paused =
        t.state == TorrentState.paused || t.state == TorrentState.finished;
    showGlassSheet<void>(
      context: context,
      title: l10n.torActionsFor(t.name),
      closeLabel: l10n.torDetailClose,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              minTileHeight: ConsolarrSpacing.minTapTarget,
              leading: Icon(paused ? Icons.play_arrow : Icons.pause),
              title: Text(paused ? l10n.torActionResume : l10n.torActionPause),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _rowAction(t, paused ? _RowAction.resume : _RowAction.pause);
              },
            ),
            ListTile(
              minTileHeight: ConsolarrSpacing.minTapTarget,
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.torActionRemove),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _rowAction(t, _RowAction.remove);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openSort() {
    final l10n = context.l10n;
    final view = ref.read(torrentViewProvider);
    showGlassSheet<void>(
      context: context,
      title: l10n.torSortTitle,
      closeLabel: l10n.torDetailClose,
      detents: GlassSheetDetents.full,
      builder: (sheetContext) => SortSheet<TorrentSort>(
        options: [
          for (final s in TorrentSort.values)
            SortOption(key: s, label: _sortLabel(l10n, s)),
        ],
        selected: view.sort,
        ascending: view.ascending,
        ascendingLabel: l10n.torSortAscending,
        descendingLabel: l10n.torSortDescending,
        saveAsDefaultLabel: l10n.torSortSaveDefault,
        applyLabel: l10n.torSortApply,
        onApply: (key, ascending, save) {
          ref
              .read(torrentViewProvider.notifier)
              .applySort(key, ascending: ascending, saveAsDefault: save);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n, TorrentSort s) => switch (s) {
    TorrentSort.name => l10n.torSortName,
    TorrentSort.status => l10n.torSortStatus,
    TorrentSort.progress => l10n.torSortProgress,
    TorrentSort.size => l10n.torSortSize,
    TorrentSort.added => l10n.torSortAdded,
    TorrentSort.ratio => l10n.torSortRatio,
    TorrentSort.label => l10n.torSortLabel,
    TorrentSort.downSpeed => l10n.torSortDownSpeed,
    TorrentSort.upSpeed => l10n.torSortUpSpeed,
    TorrentSort.timeLeft => l10n.torSortTimeLeft,
  };

  void _closeSearch() {
    _searchController.clear();
    ref.read(torrentViewProvider.notifier).setQuery('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(torrentListProvider);
    // Only a loaded list has something to act on.
    final data =
        !async.isLoading && !async.hasError && async.value is TorrentsData
        ? async.value! as TorrentsData
        : null;
    final canAct = data != null && !data.offline;
    return FloatingTopBarScaffold(
      title: l10n.torrentsTitle,
      actions: [
        if (data != null)
          IconButton(
            tooltip: l10n.torAddAction,
            icon: const Icon(Icons.add),
            onPressed: canAct ? () => showAddTorrentSheet(context) : null,
          ),
        if (data != null)
          PopupMenuButton<_MenuAction>(
            tooltip: l10n.torMenuTooltip,
            icon: const Icon(Icons.more_vert),
            onSelected: (a) {
              switch (a) {
                case _MenuAction.search:
                  setState(() => _searching = true);
                case _MenuAction.sort:
                  _openSort();
                case _MenuAction.pauseAll:
                  _bulk(
                    pause: true,
                    hashes: [for (final t in data.torrents) t.hash],
                  );
                case _MenuAction.resumeAll:
                  _bulk(
                    pause: false,
                    hashes: [for (final t in data.torrents) t.hash],
                  );
                case _MenuAction.interval:
                  showPollIntervalDialog(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _MenuAction.search,
                child: Text(l10n.torSearchAction),
              ),
              PopupMenuItem(
                value: _MenuAction.sort,
                child: Text(l10n.torSortAction),
              ),
              PopupMenuItem(
                value: _MenuAction.pauseAll,
                enabled: canAct && data.torrents.isNotEmpty,
                child: Text(l10n.torMenuPauseAll),
              ),
              PopupMenuItem(
                value: _MenuAction.resumeAll,
                enabled: canAct && data.torrents.isNotEmpty,
                child: Text(l10n.torMenuResumeAll),
              ),
              PopupMenuItem(
                value: _MenuAction.interval,
                child: Text(l10n.torMenuRefreshInterval),
              ),
            ],
          ),
      ],
      bodyBuilder: (context, padding) {
        // Order matters: Riverpod keeps the previous value through a reload
        // and through an error, so `value` alone would show the previous
        // server's torrents as current after a switch.
        if (async.isLoading) return _skeleton(padding);
        if (async.hasError) return _error(context, padding, async.error!);
        return switch (async.value) {
          null => _skeleton(padding),
          TorrentsNoServer() => _noServer(context, padding),
          final TorrentsData d => _content(context, padding, d),
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
    if (appError is DelugeHostRequired) {
      return Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: DelugeHostPicker(
          hosts: appError.hosts,
          onSelected: (host) async {
            final client = await ref.read(torrentClientProvider.future);
            if (client is DaemonHostSelection) {
              await (client as DaemonHostSelection).selectHost(host.id);
            }
            await _refresh();
          },
        ),
      );
    }
    final noHost = appError.debugDetail == delugeNoHostDetail;
    final text = connectionErrorMessage(l10n, appError);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ErrorState(
          headline: noHost ? l10n.torHostTitle : l10n.torErrorHeadline,
          message: noHost ? l10n.torHostNone : text.message,
          hint: noHost ? null : text.hint,
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
      onTap: data.offline
          ? null
          : widget.onSpeedHeaderTap ?? () => showSpeedLimitsSheet(context),
    );
  }

  Widget _tools(BuildContext context, TorrentView view) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searching)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  onChanged: ref.read(torrentViewProvider.notifier).setQuery,
                  decoration: InputDecoration(
                    hintText: l10n.torSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.torSearchClose,
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              ),
            ],
          ),
        StatusTabs(
          selected: view.tab,
          onSelected: ref.read(torrentViewProvider.notifier).setTab,
        ),
      ],
    );
  }

  Widget _rowFor(
    Torrent t,
    PendingAction? pending, {
    required bool interactive,
  }) {
    final cached = _rows[t.hash];
    if (cached != null &&
        cached.torrent == t &&
        cached.pending == pending &&
        cached.interactive == interactive) {
      return cached.widget;
    }
    final widget = TorrentRow(
      key: ValueKey(t.hash),
      torrent: t,
      pending: pending,
      onTap: interactive ? () => showTorrentDetailSheet(context, t.hash) : null,
      onLongPress: interactive ? () => _rowMenu(t) : null,
    );
    _rows[t.hash] = _RowEntry(t, pending, interactive, widget);
    return widget;
  }

  Widget _content(BuildContext context, EdgeInsets padding, TorrentsData data) {
    final l10n = context.l10n;
    final side = EdgeInsets.symmetric(horizontal: padding.horizontal / 2);
    final dim = data.offline ? 0.55 : 1.0;
    final view = ref.watch(torrentViewProvider);
    final visible = ref.watch(visibleTorrentsProvider);
    final pending = ref.watch(torrentActionsProvider.select((s) => s.rows));
    final bulk = ref.watch(torrentActionsProvider.select((s) => s.bulk));
    final bulkCount = ref.watch(
      torrentActionsProvider.select((s) => s.bulkCount),
    );

    // Forget rows that left the list.
    if (_rows.length > visible.length * 2 + 16) {
      final keep = {for (final t in visible) t.hash};
      _rows.removeWhere((hash, _) => !keep.contains(hash));
    }

    final Widget emptyBody = data.torrents.isEmpty
        ? EmptyState(
            icon: Icons.download_outlined,
            headline: l10n.torEmptyHeadline,
            message: l10n.torEmptyMessage,
          )
        : EmptyState(
            icon: Icons.filter_list_off,
            headline: l10n.torFilterEmptyHeadline,
            message: l10n.torFilterEmptyMessage,
            actionLabel: l10n.torFilterClear,
            onAction: ref.read(torrentViewProvider.notifier).clearFilters,
          );

    final top = Column(
      children: [
        if (data.offline) ...[
          _offlineBanner(l10n, data),
          const SizedBox(height: ConsolarrSpacing.sm),
        ],
        _header(data),
        if (bulk != null && bulkCount != null)
          Padding(
            padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(l10n.torBulkWorking(bulkCount)),
            ),
          ),
        const SizedBox(height: ConsolarrSpacing.sm),
        _tools(context, view),
      ],
    );

    if (visible.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: Column(
          children: [
            Padding(padding: side, child: top),
            Expanded(
              child: RefreshIndicator(onRefresh: _refresh, child: emptyBody),
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
            // The banner scrolls with the content (it must not overlap the
            // speed header the way a floating one would).
            sliver: SliverToBoxAdapter(child: top),
          ),
          SliverPadding(
            padding: EdgeInsets.only(
              top: ConsolarrSpacing.sm,
              bottom: padding.bottom,
            ).add(side),
            sliver: SliverOpacity(
              opacity: dim,
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: ConsolarrSpacing.sm),
                itemBuilder: (context, i) => _rowFor(
                  visible[i],
                  pending[visible[i].hash],
                  interactive: !data.offline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RowAction { pause, resume, remove }

class _RowEntry {
  const _RowEntry(this.torrent, this.pending, this.interactive, this.widget);

  final Torrent torrent;
  final PendingAction? pending;
  final bool interactive;
  final Widget widget;
}
