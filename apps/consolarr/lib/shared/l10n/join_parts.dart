// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';

/// Joins short facts ("2020", "4.2 GB", "WEBDL-1080p") with the localized
/// separator, so no screen hardcodes a bullet.
String joinParts(AppLocalizations l10n, Iterable<String> parts) =>
    parts.join(l10n.sharedPartSeparator);
