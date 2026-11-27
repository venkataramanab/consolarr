// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// What the user chose in the remove dialog.
class RemoveChoice {
  const RemoveChoice({required this.deleteFiles});
  final bool deleteFiles;
}

/// Confirms removing a torrent (TOR-07). "Also delete downloaded data" is
/// unchecked by default, says what it does, and changes the confirm button.
Future<RemoveChoice?> showRemoveDialog(BuildContext context, String name) {
  return showDialog<RemoveChoice>(
    context: context,
    builder: (_) => _RemoveDialog(name: name),
  );
}

class _RemoveDialog extends StatefulWidget {
  const _RemoveDialog({required this.name});

  final String name;

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.torRemoveTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.torRemoveBody(widget.name)),
            CheckboxListTile(
              value: _deleteFiles,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.torRemoveDeleteData),
              onChanged: (v) => setState(() => _deleteFiles = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.torCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(RemoveChoice(deleteFiles: _deleteFiles)),
          child: Text(
            _deleteFiles
                ? l10n.torRemoveConfirmWithData
                : l10n.torRemoveConfirm,
          ),
        ),
      ],
    );
  }
}

/// A plain confirmation with a stated consequence (pause all, resume all).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.torCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
