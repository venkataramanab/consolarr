// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Icon, row activity and chip tone of a queue [state]. State is always shown
/// as icon plus text, never by colour alone.
(IconData, ProgressRowState, StatusTone) queueStateStyle(ArrQueueState state) =>
    switch (state) {
      ArrQueueState.downloading => (
        Icons.downloading,
        ProgressRowState.active,
        StatusTone.info,
      ),
      ArrQueueState.paused => (
        Icons.pause_circle_outline,
        ProgressRowState.paused,
        StatusTone.neutral,
      ),
      ArrQueueState.queued => (
        Icons.schedule,
        ProgressRowState.queued,
        StatusTone.neutral,
      ),
      ArrQueueState.delayed => (
        Icons.hourglass_empty,
        ProgressRowState.queued,
        StatusTone.neutral,
      ),
      ArrQueueState.importPending => (
        Icons.move_to_inbox,
        ProgressRowState.idle,
        StatusTone.info,
      ),
      ArrQueueState.importing => (
        Icons.input,
        ProgressRowState.active,
        StatusTone.info,
      ),
      ArrQueueState.importFailed => (
        Icons.error_outline,
        ProgressRowState.error,
        StatusTone.error,
      ),
      ArrQueueState.downloadFailed => (
        Icons.error_outline,
        ProgressRowState.error,
        StatusTone.error,
      ),
      ArrQueueState.clientUnavailable => (
        Icons.cloud_off_outlined,
        ProgressRowState.error,
        StatusTone.error,
      ),
      ArrQueueState.warning => (
        Icons.warning_amber,
        ProgressRowState.idle,
        StatusTone.warning,
      ),
      ArrQueueState.completed => (
        Icons.check_circle_outline,
        ProgressRowState.idle,
        StatusTone.success,
      ),
      ArrQueueState.unknown => (
        Icons.help_outline,
        ProgressRowState.idle,
        StatusTone.neutral,
      ),
    };

/// One download-queue row (SON-14, later RAD-11): progress fills from the
/// leading edge, the state is icon plus text, server warnings expand as plain
/// text, and removing has a visible button (never gesture only).
///
/// Takes plain values and already-localized strings; it knows no service.
class ArrQueueRow extends StatelessWidget {
  const ArrQueueRow({
    required this.title,
    required this.state,
    required this.stateLabel,
    required this.progress,
    required this.progressLabel,
    required this.semanticsLabel,
    required this.removeLabel,
    this.details = const [],
    this.warningLabel,
    this.warningDetails,
    this.onOpen,
    this.onRemove,
    this.removeDisabledReason,
    super.key,
  });

  final String title;
  final ArrQueueState state;
  final String stateLabel;

  /// 0..1.
  final double progress;
  final String progressLabel;

  /// Full spoken description: state and percentage included.
  final String semanticsLabel;
  final List<String> details;

  /// Chip label of the server messages (for example "2 messages"); null when
  /// there are none.
  final String? warningLabel;

  /// The messages, as plain text, shown when the chip is expanded.
  final String? warningDetails;
  final VoidCallback? onOpen;

  /// Tooltip and name of the remove button.
  final String removeLabel;

  /// Null disables the button; [removeDisabledReason] then explains why.
  final VoidCallback? onRemove;
  final String? removeDisabledReason;

  @override
  Widget build(BuildContext context) {
    final (icon, rowState, _) = queueStateStyle(state);
    final hasWarning = warningLabel != null && warningDetails != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProgressFillRow(
          title: title,
          progress: progress,
          state: rowState,
          stateIcon: icon,
          stateLabel: stateLabel,
          progressLabel: progressLabel,
          semanticsLabel: semanticsLabel,
          details: details,
          onTap: onOpen,
        ),
        Row(
          children: [
            Expanded(
              child: hasWarning
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: ConsolarrSpacing.xs,
                        ),
                        child: StatusChip(
                          label: warningLabel!,
                          icon: Icons.warning_amber,
                          tone: StatusTone.warning,
                          details: warningDetails,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              tooltip: onRemove == null
                  ? (removeDisabledReason ?? removeLabel)
                  : removeLabel,
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
      ],
    );
  }
}
