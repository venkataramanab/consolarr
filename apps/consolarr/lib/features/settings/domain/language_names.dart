// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Each language written in itself (endonyms). These are deliberately not
/// translated: a person must be able to find their own language whatever the
/// current app language is.
const Map<String, String> languageEndonyms = {'ar': 'العربية', 'en': 'English'};

/// The languages the app ships (no pseudo-locale), in a stable order.
List<Locale> shippedLanguages() => [
  for (final l in supportedLocalesFor(includePseudo: false))
    if (l.countryCode == null || l.countryCode!.isEmpty) l,
];

/// The endonym for [tag], or the tag itself when unknown.
String languageName(String tag) => languageEndonyms[tag] ?? tag;
