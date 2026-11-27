// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/queue_row.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Localized state name of a queue item.
String queueStateText(AppLocalizations l10n, ArrQueueState state) =>
    switch (state) {
      ArrQueueState.downloading => l10n.arrCommonQueueStateDownloading,
      ArrQueueState.paused => l10n.arrCommonQueueStatePaused,
      ArrQueueState.queued => l10n.arrCommonQueueStateQueued,
      ArrQueueState.delayed => l10n.arrCommonQueueStateDelayed,
      ArrQueueState.importPending => l10n.arrCommonQueueStateImportPending,
      ArrQueueState.importing => l10n.arrCommonQueueStateImporting,
      ArrQueueState.importFailed => l10n.arrCommonQueueStateImportFailed,
      ArrQueueState.downloadFailed => l10n.arrCommonQueueStateDownloadFailed,
      ArrQueueState.clientUnavailable =>
        l10n.arrCommonQueueStateClientUnavailable,
      ArrQueueState.warning => l10n.arrCommonQueueStateWarning,
      ArrQueueState.completed => l10n.arrCommonQueueStateCompleted,
      ArrQueueState.unknown => l10n.arrCommonQueueStateUnknown,
    };

/// Locale-formatted size with one decimal.
String queueSizeText(AppLocalizations l10n, int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  const tb = 1024 * gb;
  if (bytes >= tb) return l10n.arrCommonQueueSizeTb(bytes / tb);
  if (bytes >= gb) return l10n.arrCommonQueueSizeGb(bytes / gb);
  return l10n.arrCommonQueueSizeMb(bytes / mb);
}

/// "12 min left", "1 h 5 min left", ...
String queueTimeLeftText(AppLocalizations l10n, Duration left) {
  if (left.inMinutes < 1) return l10n.arrCommonQueueTimeLeftLessThanMinute;
  if (left.inHours < 1)
    return l10n.arrCommonQueueTimeLeftMinutes(left.inMinutes);
  if (left.inDays < 1) {
    return l10n.arrCommonQueueTimeLeftHours(left.inHours, left.inMinutes % 60);
  }
  return l10n.arrCommonQueueTimeLeftDays(left.inDays, left.inHours % 24);
}

/// The server's messages as plain text (one block per group).
String? queueWarningText(ArrQueueItem item) {
  final lines = <String>[
    ?item.errorMessage,
    for (final m in item.messages) ...[?m.title, ...m.messages],
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// An [ArrQueueRow] for [item]. [mediaLabel] is the heading (series or movie,
/// with its own formatting); [extraDetails] go before size and time.
class ArrQueueItemRow extends StatelessWidget {
  const ArrQueueItemRow({
    required this.item,
    required this.mediaLabel,
    this.extraDetails = const [],
    this.onOpen,
    this.onRemove,
    this.removeDisabledReason,
    super.key,
  });

  final ArrQueueItem item;
  final String mediaLabel;
  final List<String> extraDetails;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;
  final String? removeDisabledReason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = queueStateText(l10n, item.state);
    final percent = l10n.arrCommonQueuePercent(item.progress.clamp(0.0, 1.0));
    final size = item.size > 0
        ? l10n.arrCommonQueueSizeProgress(
            queueSizeText(l10n, item.size - item.sizeLeft),
            queueSizeText(l10n, item.size),
          )
        : null;
    final left = item.timeLeft == null
        ? null
        : queueTimeLeftText(l10n, item.timeLeft!);
    final details = [...extraDetails, ?size, ?left, ?item.qualityName];
    final warning = queueWarningText(item);
    return ArrQueueRow(
      title: mediaLabel,
      state: item.state,
      stateLabel: state,
      progress: item.progress,
      progressLabel: percent,
      semanticsLabel: l10n.arrCommonQueueRowSemantics(
        mediaLabel,
        state,
        percent,
        details.join(', '),
      ),
      details: details,
      warningLabel: warning == null
          ? null
          : l10n.arrCommonQueueWarningCount(
              item.messages.length + (item.errorMessage == null ? 0 : 1),
            ),
      warningDetails: warning,
      removeLabel: l10n.arrCommonQueueRemoveAction,
      removeDisabledReason: removeDisabledReason,
      onOpen: onOpen,
      onRemove: onRemove,
    );
  }
}
