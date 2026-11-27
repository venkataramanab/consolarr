// SPDX-License-Identifier: GPL-3.0-or-later

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutLicense =>
      'Consolarr is free software, licensed under GPL-3.0-or-later.';

  @override
  String get aboutIndependence =>
      'Consolarr is an independent project and is not affiliated with Sonarr, Radarr, the Servarr project or any other app.';

  @override
  String get homeTitle => 'Home';

  @override
  String get homeEmptyHeading => 'Nothing here yet';

  @override
  String get homeEmptyBody =>
      'Add a media server or download client to get started. This screen is a placeholder.';

  @override
  String homeServerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servers',
      one: '1 server',
      zero: 'No servers',
    );
    return '$_temp0';
  }

  @override
  String get homeAboutTooltip => 'About Consolarr';

  @override
  String get appTitle => 'Consolarr';
}

/// The translations for English (`en_XA`).
class AppLocalizationsEnXa extends AppLocalizationsEn {
  AppLocalizationsEnXa() : super('en_XA');

  @override
  String get aboutTitle => '[Àƀöüţ~~]';

  @override
  String get aboutLicense =>
      '[Çöñšöļàŕŕ îš ƒŕéé šöƒţŵàŕé, ļîçéñšéð üñðéŕ ĜÞĻ-3.0-öŕ-ļàţéŕ.~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get aboutIndependence =>
      '[Çöñšöļàŕŕ îš àñ îñðéþéñðéñţ þŕöĵéçţ àñð îš ñöţ àƒƒîļîàţéð ŵîţĥ Šöñàŕŕ, Ŕàðàŕŕ, ţĥé Šéŕṽàŕŕ þŕöĵéçţ öŕ àñý öţĥéŕ àþþ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get homeTitle => '[Ĥöɱé~~]';

  @override
  String get homeEmptyHeading => '[Ñöţĥîñĝ ĥéŕé ýéţ~~~~~~~]';

  @override
  String get homeEmptyBody =>
      '[Àðð à ɱéðîà šéŕṽéŕ öŕ ðöŵñļöàð çļîéñţ ţö ĝéţ šţàŕţéð. Ţĥîš šçŕééñ îš à þļàçéĥöļðéŕ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String homeServerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count šéŕṽéŕš~~~~',
      one: '1 šéŕṽéŕ~~~~',
      zero: 'Ñö šéŕṽéŕš~~~~',
    );
    return '$_temp0';
  }

  @override
  String get homeAboutTooltip => '[Àƀöüţ Çöñšöļàŕŕ~~~~~~]';

  @override
  String get appTitle => '[Çöñšöļàŕŕ~~~~]';
}
