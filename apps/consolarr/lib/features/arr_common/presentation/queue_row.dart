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
      ArrQueueState.ignored => (
        Icons.visibility_off_outlined,
        ProgressRowState.idle,
        StatusTone.neutral,
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
                        child: _WarningToggle(
                          label: warningLabel!,
                          details: warningDetails!,
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

/// The server's messages behind a labelled toggle: icon, text and expanded
/// state, never colour alone. Plain text only.
class _WarningToggle extends StatefulWidget {
  const _WarningToggle({required this.label, required this.details});

  final String label;
  final String details;

  @override
  State<_WarningToggle> createState() => _WarningToggleState();
}

class _WarningToggleState extends State<_WarningToggle> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: widget.label,
          excludeSemantics: true,
          onTap: () => setState(() => _expanded = !_expanded),
          child: InkWell(
            borderRadius: ConsolarrRadii.chip,
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ConsolarrSpacing.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ConsolarrSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber, size: 18),
                    const SizedBox(width: ConsolarrSpacing.xs),
                    Flexible(
                      child: Text(
                        widget.label,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ConsolarrSpacing.sm,
            ),
            child: Text(widget.details, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}
