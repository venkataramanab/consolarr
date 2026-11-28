// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';

/// Joins short facts ("2020", "4.2 GB", "WEBDL-1080p") with the localized
/// separator, so no screen hardcodes a bullet.
String joinParts(AppLocalizations l10n, Iterable<String> parts) =>
    parts.join(l10n.sharedPartSeparator);

/// Joins the items of a list (genres, tags, the pieces of a spoken label)
/// with the localized list separator (the Arabic comma in `ar`). Nulls and
/// empty strings are dropped.
String joinList(AppLocalizations l10n, Iterable<String?> parts) => [
  for (final p in parts)
    if (p != null && p.isNotEmpty) p,
].join(l10n.sharedListSeparator);

/// Joins sentences of one spoken label with the localized separator.
String joinSentences(AppLocalizations l10n, Iterable<String?> parts) => [
  for (final p in parts)
    if (p != null && p.isNotEmpty) p,
].join(l10n.sharedSentenceSeparator);
