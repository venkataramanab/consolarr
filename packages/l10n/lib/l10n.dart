// SPDX-License-Identifier: GPL-3.0-or-later

/// Generated localizations. Do not add strings here: edit the per-feature
/// ARB files under `apps/consolarr/lib/features/<feature>/l10n/` and run
/// `melos run l10n`.
library;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:l10n/src/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

export 'package:l10n/src/generated/app_localizations.dart';

/// `context.l10n.someKey` shorthand.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Delegates for `MaterialApp.localizationsDelegates`: Consolarr's strings
/// plus the Material, Widgets and Cupertino built-ins from `material_ui`.
///
/// Use this instead of the generated `AppLocalizations.localizationsDelegates`,
/// which still points at the legacy `flutter_localizations` Material delegate.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// Whether [locale] is the generated accent/expansion pseudo-locale (`en_XA`)
/// used only to find truncation and layout bugs.
bool isPseudoLocale(Locale locale) =>
    locale.languageCode == 'en' && locale.countryCode == 'XA';

/// The generated locales, without the pseudo-locale unless [includePseudo].
List<Locale> supportedLocalesFor({required bool includePseudo}) => [
  for (final locale in AppLocalizations.supportedLocales)
    if (includePseudo || !isPseudoLocale(locale)) locale,
];

/// Locales for `MaterialApp.supportedLocales`: every generated locale in
/// debug and profile builds (so `en_XA` can be selected for testing), but
/// never the pseudo-locale in release builds.
final List<Locale> appSupportedLocales = supportedLocalesFor(
  includePseudo: !kReleaseMode,
);

/// Number formats the generated messages cannot express.
extension AppLocalizationsNumbers on AppLocalizations {
  /// [value] in the locale's digits (Arabic-Indic for `ar`) without a
  /// thousands separator: for a port or an id, where grouping would change the
  /// meaning. Falls back to plain digits for a locale intl does not know.
  String plainInt(int value) {
    try {
      return NumberFormat('0', localeName).format(value);
    } on Object {
      return '$value';
    }
  }
}
