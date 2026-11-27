// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Which search the dialog confirms.
enum SearchConfirmKind { season, series }

/// Asks before a costly search (SON-17) and states what it does. Resolves to
/// true on confirm.
Future<bool> confirmSearch(BuildContext context, SearchConfirmKind kind) async {
  final l10n = context.l10n;
  final season = kind == SearchConfirmKind.season;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        season
            ? l10n.sonarrDetailSearchSeasonTitle
            : l10n.sonarrDetailSearchSeriesTitle,
      ),
      content: Text(
        season
            ? l10n.sonarrDetailSearchSeasonMessage
            : l10n.sonarrDetailSearchSeriesMessage,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.sonarrDetailCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.sonarrDetailSearchConfirmAction),
        ),
      ],
    ),
  );
  return result ?? false;
}
