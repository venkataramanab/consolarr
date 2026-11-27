// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The refresh interval choices (TOR-18). The choice is saved at once.
Future<void> showPollIntervalDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PollDialog());

class _PollDialog extends ConsumerWidget {
  const _PollDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current =
        ref.watch(torrentPollSecondsProvider).value ?? defaultPollSeconds;
    return AlertDialog(
      title: Text(l10n.torPollTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<int>(
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(torrentPollSecondsProvider.notifier).choose(v);
                }
              },
              child: Column(
                children: [
                  for (final s in pollSecondsChoices)
                    RadioListTile<int>(
                      value: s,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.torPollOption(s)),
                    ),
                ],
              ),
            ),
            Text(
              l10n.torPollHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.torPollClose),
        ),
      ],
    );
  }
}
