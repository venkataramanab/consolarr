// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrent_actions_controller.dart';
import 'package:consolarr/features/torrents/application/torrent_detail_provider.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/error_text.dart';
import 'package:consolarr/features/torrents/presentation/format.dart';
import 'package:consolarr/features/torrents/presentation/remove_dialog.dart';
import 'package:consolarr/features/torrents/presentation/screen_view.dart';
import 'package:consolarr/features/torrents/presentation/stand_ins/glass_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_state_view.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Opens the detail sheet of the torrent with [hash] (TOR-08, overview).
Future<void> showTorrentDetailSheet(BuildContext context, String hash) {
  final l10n = context.l10n;
  return showGlassSheet<void>(
    context: context,
    title: l10n.torDetailTitle,
    closeLabel: l10n.torDetailClose,
    detents: GlassSheetDetents.full,
    builder: (_) => TorrentDetailSheet(hash: hash),
  );
}

/// The overview page: save path (copyable), ratio, transferred, added date,
/// seeds and peers, availability and ETA, plus pause/resume and remove. It
/// refreshes at the list's interval, only while it is open and the app is
/// visible.
class TorrentDetailSheet extends ConsumerStatefulWidget {
  const TorrentDetailSheet({required this.hash, super.key});

  final String hash;

  @override
  ConsumerState<TorrentDetailSheet> createState() => _TorrentDetailSheetState();
}

class _TorrentDetailSheetState extends ConsumerState<TorrentDetailSheet>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _resumed = true;
  String? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(ref.read(torrentPollIntervalProvider), (_) {
      if (mounted && _resumed) {
        unawaited(
          ref.read(torrentDetailProvider(widget.hash).notifier).refresh(),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _resumed = state == AppLifecycleState.resumed;

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _run(Future<Result<void>> Function() action) async {
    final r = await action();
    if (!mounted) return;
    final error = r.errorOrNull;
    setState(
      () => _failure = error == null
          ? null
          : context.l10n.torActionFailed(
              torrentErrorReason(context.l10n, error),
            ),
    );
    if (error == null) {
      unawaited(
        ref.read(torrentDetailProvider(widget.hash).notifier).refresh(),
      );
    }
  }

  Future<void> _remove(String name) async {
    final choice = await showRemoveDialog(context, name);
    if (choice == null || !mounted) return;
    final r = await ref
        .read(torrentActionsProvider.notifier)
        .remove(widget.hash, deleteFiles: choice.deleteFiles);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).maybePop();
    } else {
      setState(
        () => _failure = context.l10n.torActionFailed(
          torrentErrorReason(context.l10n, r.errorOrNull!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(torrentDetailProvider(widget.hash));
    return TorrentScreenView(
      screen: ScreenName.torrentDetail,
      // Loading first, then error: a reload keeps the previous value.
      child: async.isLoading
          ? _skeleton()
          : async.hasError
          ? _error(l10n, appErrorOrUnknown(async.error!))
          : _content(l10n, async.requireValue),
    );
  }

  Widget _skeleton() => const Padding(
    padding: EdgeInsets.all(ConsolarrSpacing.gutter),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonBox(height: 56),
        SizedBox(height: ConsolarrSpacing.sm),
        SkeletonBox(height: 220),
      ],
    ),
  );

  Widget _error(AppLocalizations l10n, AppError error) {
    final text = connectionErrorMessage(l10n, error);
    return SingleChildScrollView(
      child: ErrorState(
        headline: l10n.torDetailErrorHeadline,
        message: text.message,
        hint: text.hint,
        retryLabel: l10n.torRetry,
        onRetry: () => ref.invalidate(torrentDetailProvider(widget.hash)),
      ),
    );
  }

  Widget _row(String label, String value, {Widget? trailing}) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ConsolarrSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: ConsolarrTypeScale.tabularFigures,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  String _count(AppLocalizations l10n, int? connected, int? total) {
    if (connected == null && total == null) return l10n.torDetailUnknown;
    if (connected != null && total != null) {
      return l10n.torDetailCountOf(connected, total);
    }
    return '${connected ?? total}';
  }

  Widget _content(AppLocalizations l10n, TorrentDetail d) {
    final t = d.torrent;
    final view = torrentStateView(l10n, t.state);
    final pending = ref.watch(
      torrentActionsProvider.select((s) => s.rows[widget.hash]),
    );
    final caps = ref.watch(torrentCapabilitiesProvider);
    final unknown = l10n.torDetailUnknown;
    final noSeeds =
        (t.state == TorrentState.downloading ||
            t.state == TorrentState.stalled) &&
        d.seeds == 0 &&
        (d.seedsTotal ?? 0) == 0;
    final paused =
        t.state == TorrentState.paused || t.state == TorrentState.finished;
    final added = t.addedOn;
    final path = d.savePath;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.gutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: ConsolarrSpacing.xs),
          Row(
            children: [
              Icon(view.icon, size: 20),
              const SizedBox(width: ConsolarrSpacing.sm),
              Expanded(
                child: Text(
                  '${view.label} · ${l10n.torProgressPercent(t.progress)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: ConsolarrSpacing.sm),
          if (noSeeds)
            Padding(
              padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: context.roles.warning,
                  ),
                  const SizedBox(width: ConsolarrSpacing.sm),
                  Expanded(child: Text(l10n.torDetailNoSeeds)),
                ],
              ),
            ),
          _row(
            l10n.torDetailSavePath,
            path ?? unknown,
            trailing: path == null
                ? null
                : IconButton(
                    tooltip: l10n.torDetailCopyPath,
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      // User-initiated copy of the save path only.
                      await Clipboard.setData(ClipboardData(text: path));
                      if (!mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(content: Text(l10n.torDetailPathCopied)),
                      );
                    },
                  ),
          ),
          _row(l10n.torDetailRatioLabel, l10n.torDetailRatio(t.ratio)),
          _row(
            l10n.torDetailDownloaded,
            d.downloaded == null ? unknown : formatBytes(l10n, d.downloaded!),
          ),
          _row(
            l10n.torDetailUploaded,
            d.uploaded == null ? unknown : formatBytes(l10n, d.uploaded!),
          ),
          _row(
            l10n.torDetailAdded,
            added == null
                ? unknown
                : MaterialLocalizations.of(context)
                      .formatMediumDate(added.toLocal()),
          ),
          _row(l10n.torDetailSeeds, _count(l10n, d.seeds, d.seedsTotal)),
          _row(l10n.torDetailPeers, _count(l10n, d.peers, d.peersTotal)),
          if (caps.availability && d.availability != null)
            _row(
              l10n.torDetailAvailability,
              l10n.torDetailAvailabilityValue(d.availability!),
            ),
          _row(
            l10n.torDetailEtaLabel,
            t.eta == null ? unknown : formatDuration(l10n, t.eta!),
          ),
          if (_failure != null)
            Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
              child: Semantics(liveRegion: true, child: Text(_failure!)),
            ),
          const SizedBox(height: ConsolarrSpacing.md),
          Wrap(
            spacing: ConsolarrSpacing.sm,
            runSpacing: ConsolarrSpacing.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed: pending != null
                    ? null
                    : () => _run(
                        () => paused
                            ? ref
                                  .read(torrentActionsProvider.notifier)
                                  .resume(widget.hash)
                            : ref
                                  .read(torrentActionsProvider.notifier)
                                  .pause(widget.hash),
                      ),
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(switch (pending) {
                  PendingAction.pausing => l10n.torPendingPausing,
                  PendingAction.resuming => l10n.torPendingResuming,
                  PendingAction.removing => l10n.torPendingRemoving,
                  null => paused ? l10n.torActionResume : l10n.torActionPause,
                }),
              ),
              OutlinedButton.icon(
                onPressed: pending != null ? null : () => _remove(t.name),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.torActionRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
