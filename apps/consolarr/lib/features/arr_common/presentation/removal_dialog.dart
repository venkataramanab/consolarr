// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// What the user chose in the removal dialog.
class ArrQueueRemovalChoice {
  const ArrQueueRemovalChoice({
    required this.removeFromClient,
    required this.blocklist,
  });

  /// Also delete the download (and its files) in the download client.
  final bool removeFromClient;
  final ArrBlocklistChoice blocklist;
}

/// Opens the destructive confirm for removing a queue item (SON-15).
///
/// The dialog states the consequences in words: deleting from the download
/// client, and what each blocklist choice does. [onConfirm] performs the
/// removal and returns null on success or the [AppError] on failure; while it
/// runs both buttons are disabled (no double submit), and after a failure the
/// error is shown with a retry. Resolves to true once removed.
Future<bool> showArrQueueRemovalDialog({
  required BuildContext context,
  required String itemLabel,
  required String serviceName,
  required Future<AppError?> Function(ArrQueueRemovalChoice choice) onConfirm,
}) async {
  final removed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _RemovalDialog(
      itemLabel: itemLabel,
      serviceName: serviceName,
      onConfirm: onConfirm,
    ),
  );
  return removed ?? false;
}

class _RemovalDialog extends StatefulWidget {
  const _RemovalDialog({
    required this.itemLabel,
    required this.serviceName,
    required this.onConfirm,
  });

  final String itemLabel;
  final String serviceName;
  final Future<AppError?> Function(ArrQueueRemovalChoice choice) onConfirm;

  @override
  State<_RemovalDialog> createState() => _RemovalDialogState();
}

class _RemovalDialogState extends State<_RemovalDialog> {
  bool _fromClient = true;
  ArrBlocklistChoice _blocklist = ArrBlocklistChoice.none;
  bool _busy = false;
  AppError? _error;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onConfirm(
      ArrQueueRemovalChoice(
        removeFromClient: _fromClient,
        blocklist: _blocklist,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final error = _error;
    final message = error == null ? null : connectionErrorMessage(l10n, error);
    return AlertDialog(
      title: Text(l10n.arrCommonQueueRemoveTitle),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.itemLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: context.roles.textPrimary,
            ),
          ),
          const SizedBox(height: ConsolarrSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.arrCommonQueueRemoveFromClientTitle),
            subtitle: Text(
              _fromClient
                  ? l10n.arrCommonQueueRemoveFromClientOn
                  : l10n.arrCommonQueueRemoveFromClientOff(widget.serviceName),
            ),
            value: _fromClient,
            onChanged: _busy ? null : (v) => setState(() => _fromClient = v),
          ),
          const SizedBox(height: ConsolarrSpacing.sm),
          Semantics(
            header: true,
            child: Text(
              l10n.arrCommonQueueBlocklistHeading,
              style: theme.textTheme.titleSmall?.copyWith(
                color: context.roles.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _ChoiceTile(
            label: l10n.arrCommonQueueBlocklistNone,
            detail: l10n.arrCommonQueueBlocklistNoneDetail,
            selected: _blocklist == ArrBlocklistChoice.none,
            onTap: _busy
                ? null
                : () => setState(() => _blocklist = ArrBlocklistChoice.none),
          ),
          _ChoiceTile(
            label: l10n.arrCommonQueueBlocklistSearch,
            detail: l10n.arrCommonQueueBlocklistSearchDetail(
              widget.serviceName,
            ),
            selected: _blocklist == ArrBlocklistChoice.blocklistAndSearch,
            onTap: _busy
                ? null
                : () => setState(
                    () => _blocklist = ArrBlocklistChoice.blocklistAndSearch,
                  ),
          ),
          _ChoiceTile(
            label: l10n.arrCommonQueueBlocklistOnly,
            detail: l10n.arrCommonQueueBlocklistOnlyDetail,
            selected: _blocklist == ArrBlocklistChoice.blocklistOnly,
            onTap: _busy
                ? null
                : () => setState(
                    () => _blocklist = ArrBlocklistChoice.blocklistOnly,
                  ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
              child: Semantics(
                liveRegion: true,
                label: l10n.arrCommonQueueRemoving,
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Flexible(child: Text(l10n.arrCommonQueueRemoving)),
                  ],
                ),
              ),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.md),
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.arrCommonQueueRemoveFailed,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: context.roles.error,
                      ),
                    ),
                    Text(message.message),
                    Text(message.hint),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.arrCommonQueueRemoveCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(
            error == null
                ? l10n.arrCommonQueueRemoveConfirm
                : l10n.arrCommonQueueRemoveRetry,
          ),
        ),
      ],
    );
  }
}

/// A radio-style choice with a consequence line. Selection is icon plus
/// semantics state, never colour alone.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: onTap != null,
      label: '$label. $detail',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: ConsolarrSpacing.minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ConsolarrSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                ),
                const SizedBox(width: ConsolarrSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodyLarge),
                      Text(detail, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
