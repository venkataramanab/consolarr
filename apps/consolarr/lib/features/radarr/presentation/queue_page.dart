// SPDX-License-Identifier: GPL-3.0-or-later

// TODO(arr_common): the queue row and the removal dialog are local copies;
// swap them for the shared ones from `features/arr_common` once W4a merges.

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/poller.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
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
        RadarrData(:final value) when value.isEmpty => pane(
          EmptyState(
            icon: Icons.download_done,
            headline: context.l10n.radarrQueueEmptyHeadline,
            message: context.l10n.radarrQueueEmptyMessage,
          ),
        ),
        RadarrData(:final value) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            itemCount: value.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: QueueRow(key: ValueKey(value[i].id), item: value[i]),
            ),
          ),
        ),
      };
    }
    return RadarrScreenView(
      screen: ScreenName.radarrQueue,
      child: VisiblePoller(active: active, onTick: refresh, child: body),
    );
  }
}

(IconData, String, ProgressRowState) _status(
  AppLocalizations l10n,
  RadarrQueueItem q,
) {
  if (q.trackedStatus == 'error' || q.trackedState == 'importFailed') {
    return (
      Icons.error_outline,
      l10n.radarrQueueImportFailed,
      ProgressRowState.error,
    );
  }
  return switch (q.trackedState) {
    'importPending' || 'importing' => (
      Icons.move_to_inbox,
      l10n.radarrQueueImportPending,
      ProgressRowState.idle,
    ),
    'importBlocked' => (
      Icons.block,
      l10n.radarrQueueImportBlocked,
      ProgressRowState.error,
    ),
    'downloadFailed' || 'failedPending' => (
      Icons.error_outline,
      l10n.radarrQueueFailed,
      ProgressRowState.error,
    ),
    _ => switch (q.status) {
      'paused' => (
        Icons.pause_circle_outline,
        l10n.radarrQueuePaused,
        ProgressRowState.paused,
      ),
      'queued' => (
        Icons.schedule,
        l10n.radarrQueueQueued,
        ProgressRowState.queued,
      ),
      'delay' => (
        Icons.hourglass_empty,
        l10n.radarrQueueDelayed,
        ProgressRowState.queued,
      ),
      'downloadClientUnavailable' => (
        Icons.cloud_off,
        l10n.radarrQueueClientUnavailable,
        ProgressRowState.error,
      ),
      'completed' => (
        Icons.check_circle_outline,
        l10n.radarrQueueCompleted,
        ProgressRowState.idle,
      ),
      'warning' => (
        Icons.warning_amber,
        l10n.radarrQueueWarning,
        ProgressRowState.idle,
      ),
      _ => (
        Icons.downloading,
        l10n.radarrQueueDownloading,
        ProgressRowState.active,
      ),
    },
  };
}

String timeLeftText(AppLocalizations l10n, Duration d) {
  if (d.inHours >= 1)
    return l10n.radarrTimeLeftHours(d.inHours, d.inMinutes % 60);
  if (d.inMinutes >= 1) return l10n.radarrTimeLeftMinutes(d.inMinutes);
  return l10n.radarrTimeLeftSeconds(d.inSeconds);
}

class QueueRow extends ConsumerWidget {
  const QueueRow({required this.item, super.key});

  final RadarrQueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final (icon, stateText, rowState) = _status(l10n, item);
    final percent = (item.progress * 100).round();
    final left = item.timeLeft;
    final details = [
      sizeText(l10n, item.size),
      if (left != null) timeLeftText(l10n, left),
      ?item.downloadClient,
    ];
    final title = item.title ?? l10n.radarrQueueUnknownRelease;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProgressFillRow(
          title: title,
          progress: item.progress,
          state: rowState,
          stateIcon: icon,
          stateLabel: stateText,
          progressLabel: l10n.radarrPercent(percent),
          details: details,
          semanticsLabel: l10n.radarrQueueSemantics(title, stateText, percent),
          onTap: item.movieId == null
              ? null
              : () => openMovie(context, item.movieId!),
        ),
        if (item.messages.isNotEmpty) _MessagesPanel(messages: item.messages),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => _remove(context, ref),
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.radarrQueueRemove),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final choice = await showDialog<RemovalChoice>(
      context: context,
      builder: (_) => const RemovalDialog(),
    );
    if (choice == null || !context.mounted) return;
    final error = await ref
        .read(queueProvider.notifier)
        .remove(
          item,
          removeFromClient: choice.removeFromClient,
          blocklist: choice.blocklist,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? l10n.radarrQueueRemoved
              : '${l10n.radarrQueueRemoveFailed} ${connectionErrorMessage(l10n, error).message}',
        ),
      ),
    );
  }
}

class RemovalChoice {
  const RemovalChoice(this.removeFromClient, this.blocklist);
  final bool removeFromClient;
  final QueueBlocklist blocklist;
}

/// Removal choices and what each one does (same wording as the Sonarr queue).
class RemovalDialog extends StatefulWidget {
  const RemovalDialog({super.key});

  @override
  State<RemovalDialog> createState() => _RemovalDialogState();
}

class _RemovalDialogState extends State<RemovalDialog> {
  bool _fromClient = true;
  QueueBlocklist _blocklist = QueueBlocklist.none;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final consequence = [
      _fromClient
          ? l10n.radarrRemoveConsequenceClient
          : l10n.radarrRemoveConsequenceKeep,
      switch (_blocklist) {
        QueueBlocklist.none => l10n.radarrRemoveConsequenceNoBlocklist,
        QueueBlocklist.blocklistAndSearch =>
          l10n.radarrRemoveConsequenceBlocklistSearch,
        QueueBlocklist.blocklistOnly =>
          l10n.radarrRemoveConsequenceBlocklistOnly,
      },
    ].join(' ');
    return AlertDialog(
      title: Text(l10n.radarrRemoveTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<bool>(
              groupValue: _fromClient,
              onChanged: (v) => setState(() => _fromClient = v ?? true),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: true,
                    title: Text(l10n.radarrRemoveFromClient),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    title: Text(l10n.radarrRemoveOnlyRadarr),
                  ),
                ],
              ),
            ),
            const Divider(),
            RadioGroup<QueueBlocklist>(
              groupValue: _blocklist,
              onChanged: (v) =>
                  setState(() => _blocklist = v ?? QueueBlocklist.none),
              child: Column(
                children: [
                  RadioListTile<QueueBlocklist>(
                    value: QueueBlocklist.none,
                    title: Text(l10n.radarrBlocklistNone),
                  ),
                  RadioListTile<QueueBlocklist>(
                    value: QueueBlocklist.blocklistAndSearch,
                    title: Text(l10n.radarrBlocklistAndSearch),
                  ),
                  RadioListTile<QueueBlocklist>(
                    value: QueueBlocklist.blocklistOnly,
                    title: Text(l10n.radarrBlocklistOnly),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ConsolarrSpacing.sm),
            Semantics(liveRegion: true, child: Text(consequence)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.radarrCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(RemovalChoice(_fromClient, _blocklist)),
          child: Text(l10n.radarrRemoveConfirm),
        ),
      ],
    );
  }
}

/// Expandable warning and error texts of a queue item (plain text).
class _MessagesPanel extends StatefulWidget {
  const _MessagesPanel({required this.messages});

  final List<String> messages;

  @override
  State<_MessagesPanel> createState() => _MessagesPanelState();
}

class _MessagesPanelState extends State<_MessagesPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.warning_amber),
          label: Text(l10n.radarrQueueMessages(widget.messages.length)),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: ConsolarrSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final m in widget.messages) Text('• $m')],
            ),
          ),
      ],
    );
  }
}
