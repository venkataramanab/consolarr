// SPDX-License-Identifier: GPL-3.0-or-later

/// Generated localizations. Do not add strings here: edit the per-feature
/// ARB files under `apps/consolarr/lib/features/<feature>/l10n/` and run
/// `melos run l10n`.
library;

import 'package:flutter/widgets.dart';
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
