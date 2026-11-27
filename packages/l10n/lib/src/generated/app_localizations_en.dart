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
  String get connErrorAuthFailedMessage =>
      'The server rejected the credentials.';

  @override
  String get connErrorAuthFailedHint =>
      'Check the API key or the username and password, then test again.';

  @override
  String get connErrorNeedsCredentialsMessage =>
      'This server\'s saved credentials are missing.';

  @override
  String get connErrorNeedsCredentialsHint =>
      'This can happen after a device restore or a lock screen change. Enter the credentials again.';

  @override
  String get connErrorTimeoutMessage => 'The server did not answer in time.';

  @override
  String get connErrorTimeoutHint =>
      'Check that it is running and reachable from this network, or try again.';

  @override
  String get connErrorTlsPinMismatchMessage =>
      'The server\'s certificate is different from the one you trusted.';

  @override
  String get connErrorTlsPinMismatchHint =>
      'Connections are blocked. Only trust the new certificate if you know the server\'s certificate was replaced.';

  @override
  String get connErrorTlsUntrustedMessage =>
      'The server\'s certificate is not trusted by this device.';

  @override
  String get connErrorTlsUntrustedHint =>
      'If this is your own server with a self-signed certificate, review its fingerprint and choose whether to trust it.';

  @override
  String get connErrorTlsExpiredMessage =>
      'The server\'s certificate has expired or is not valid yet.';

  @override
  String get connErrorTlsExpiredHint =>
      'Renew the certificate on the server, or check the date on this device.';

  @override
  String get connErrorCleartextRefusedMessage =>
      'This address uses plain http, which is not allowed for this server.';

  @override
  String get connErrorCleartextRefusedHint =>
      'Use an https address, or allow plain http for this server in its security settings if it is on a network you trust.';

  @override
  String get connErrorUnsupportedVersionMessage =>
      'This server version is not supported.';

  @override
  String get connErrorUnsupportedVersionHint =>
      'Update the server to a current major version.';

  @override
  String get connErrorNotFoundMessage => 'Nothing was found at this address.';

  @override
  String get connErrorNotFoundHint =>
      'Check the address, port and path prefix. A reverse proxy often needs a prefix such as /sonarr.';

  @override
  String get connErrorServerErrorMessage => 'The server reported an error.';

  @override
  String get connErrorServerErrorHint =>
      'Try again in a moment. If it keeps happening, check the server\'s own logs.';

  @override
  String get connErrorNetworkUnreachableMessage =>
      'The server could not be reached.';

  @override
  String get connErrorNetworkUnreachableHint =>
      'Check the address and port, that the server is running, and that this device is on the right network.';

  @override
  String get connErrorParseErrorMessage =>
      'The server\'s reply could not be understood.';

  @override
  String get connErrorParseErrorHint =>
      'Check that the address points at the right service and not at a login page or proxy.';

  @override
  String get connErrorRedirectRefusedMessage =>
      'The server redirected the request somewhere that is not allowed.';

  @override
  String get connErrorRedirectRefusedHint =>
      'Use the final address of the server directly, and https if it redirects from https to http.';

  @override
  String get connErrorResponseTooLargeMessage =>
      'The server\'s reply was too large.';

  @override
  String get connErrorResponseTooLargeHint =>
      'Check that the address points at the right service.';

  @override
  String get connErrorInvalidInputMessage =>
      'The address or path is not valid.';

  @override
  String get connErrorInvalidInputHint =>
      'Enter an address like https://host:port without a username, password or key, and a path that starts with a slash.';

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
  String get connErrorAuthFailedMessage =>
      '[Ţĥé šéŕṽéŕ ŕéĵéçţéð ţĥé çŕéðéñţîàļš.~~~~~~~~~~~~~~~]';

  @override
  String get connErrorAuthFailedHint =>
      '[Çĥéçķ ţĥé ÀÞÎ ķéý öŕ ţĥé üšéŕñàɱé àñð þàššŵöŕð, ţĥéñ ţéšţ àĝàîñ.~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorNeedsCredentialsMessage =>
      '[Ţĥîš šéŕṽéŕ\'š šàṽéð çŕéðéñţîàļš àŕé ɱîššîñĝ.~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorNeedsCredentialsHint =>
      '[Ţĥîš çàñ ĥàþþéñ àƒţéŕ à ðéṽîçé ŕéšţöŕé öŕ à ļöçķ šçŕééñ çĥàñĝé. Éñţéŕ ţĥé çŕéðéñţîàļš àĝàîñ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTimeoutMessage =>
      '[Ţĥé šéŕṽéŕ ðîð ñöţ àñšŵéŕ îñ ţîɱé.~~~~~~~~~~~~~~]';

  @override
  String get connErrorTimeoutHint =>
      '[Çĥéçķ ţĥàţ îţ îš ŕüññîñĝ àñð ŕéàçĥàƀļé ƒŕöɱ ţĥîš ñéţŵöŕķ, öŕ ţŕý àĝàîñ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTlsPinMismatchMessage =>
      '[Ţĥé šéŕṽéŕ\'š çéŕţîƒîçàţé îš ðîƒƒéŕéñţ ƒŕöɱ ţĥé öñé ýöü ţŕüšţéð.~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTlsPinMismatchHint =>
      '[Çöññéçţîöñš àŕé ƀļöçķéð. Öñļý ţŕüšţ ţĥé ñéŵ çéŕţîƒîçàţé îƒ ýöü ķñöŵ ţĥé šéŕṽéŕ\'š çéŕţîƒîçàţé ŵàš ŕéþļàçéð.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTlsUntrustedMessage =>
      '[Ţĥé šéŕṽéŕ\'š çéŕţîƒîçàţé îš ñöţ ţŕüšţéð ƀý ţĥîš ðéṽîçé.~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTlsUntrustedHint =>
      '[Îƒ ţĥîš îš ýöüŕ öŵñ šéŕṽéŕ ŵîţĥ à šéļƒ-šîĝñéð çéŕţîƒîçàţé, ŕéṽîéŵ îţš ƒîñĝéŕþŕîñţ àñð çĥööšé ŵĥéţĥéŕ ţö ţŕüšţ îţ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTlsExpiredMessage =>
      '[Ţĥé šéŕṽéŕ\'š çéŕţîƒîçàţé ĥàš éẋþîŕéð öŕ îš ñöţ ṽàļîð ýéţ.~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorTlsExpiredHint =>
      '[Ŕéñéŵ ţĥé çéŕţîƒîçàţé öñ ţĥé šéŕṽéŕ, öŕ çĥéçķ ţĥé ðàţé öñ ţĥîš ðéṽîçé.~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorCleartextRefusedMessage =>
      '[Ţĥîš àððŕéšš üšéš þļàîñ ĥţţþ, ŵĥîçĥ îš ñöţ àļļöŵéð ƒöŕ ţĥîš šéŕṽéŕ.~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorCleartextRefusedHint =>
      '[Üšé àñ ĥţţþš àððŕéšš, öŕ àļļöŵ þļàîñ ĥţţþ ƒöŕ ţĥîš šéŕṽéŕ îñ îţš šéçüŕîţý šéţţîñĝš îƒ îţ îš öñ à ñéţŵöŕķ ýöü ţŕüšţ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorUnsupportedVersionMessage =>
      '[Ţĥîš šéŕṽéŕ ṽéŕšîöñ îš ñöţ šüþþöŕţéð.~~~~~~~~~~~~~~~]';

  @override
  String get connErrorUnsupportedVersionHint =>
      '[Üþðàţé ţĥé šéŕṽéŕ ţö à çüŕŕéñţ ɱàĵöŕ ṽéŕšîöñ.~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorNotFoundMessage =>
      '[Ñöţĥîñĝ ŵàš ƒöüñð àţ ţĥîš àððŕéšš.~~~~~~~~~~~~~~]';

  @override
  String get connErrorNotFoundHint =>
      '[Çĥéçķ ţĥé àððŕéšš, þöŕţ àñð þàţĥ þŕéƒîẋ. À ŕéṽéŕšé þŕöẋý öƒţéñ ñééðš à þŕéƒîẋ šüçĥ àš /šöñàŕŕ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorServerErrorMessage =>
      '[Ţĥé šéŕṽéŕ ŕéþöŕţéð àñ éŕŕöŕ.~~~~~~~~~~~~]';

  @override
  String get connErrorServerErrorHint =>
      '[Ţŕý àĝàîñ îñ à ɱöɱéñţ. Îƒ îţ ķééþš ĥàþþéñîñĝ, çĥéçķ ţĥé šéŕṽéŕ\'š öŵñ ļöĝš.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorNetworkUnreachableMessage =>
      '[Ţĥé šéŕṽéŕ çöüļð ñöţ ƀé ŕéàçĥéð.~~~~~~~~~~~~~]';

  @override
  String get connErrorNetworkUnreachableHint =>
      '[Çĥéçķ ţĥé àððŕéšš àñð þöŕţ, ţĥàţ ţĥé šéŕṽéŕ îš ŕüññîñĝ, àñð ţĥàţ ţĥîš ðéṽîçé îš öñ ţĥé ŕîĝĥţ ñéţŵöŕķ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorParseErrorMessage =>
      '[Ţĥé šéŕṽéŕ\'š ŕéþļý çöüļð ñöţ ƀé üñðéŕšţööð.~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorParseErrorHint =>
      '[Çĥéçķ ţĥàţ ţĥé àððŕéšš þöîñţš àţ ţĥé ŕîĝĥţ šéŕṽîçé àñð ñöţ àţ à ļöĝîñ þàĝé öŕ þŕöẋý.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorRedirectRefusedMessage =>
      '[Ţĥé šéŕṽéŕ ŕéðîŕéçţéð ţĥé ŕéǫüéšţ šöɱéŵĥéŕé ţĥàţ îš ñöţ àļļöŵéð.~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorRedirectRefusedHint =>
      '[Üšé ţĥé ƒîñàļ àððŕéšš öƒ ţĥé šéŕṽéŕ ðîŕéçţļý, àñð ĥţţþš îƒ îţ ŕéðîŕéçţš ƒŕöɱ ĥţţþš ţö ĥţţþ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorResponseTooLargeMessage =>
      '[Ţĥé šéŕṽéŕ\'š ŕéþļý ŵàš ţöö ļàŕĝé.~~~~~~~~~~~~~~]';

  @override
  String get connErrorResponseTooLargeHint =>
      '[Çĥéçķ ţĥàţ ţĥé àððŕéšš þöîñţš àţ ţĥé ŕîĝĥţ šéŕṽîçé.~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get connErrorInvalidInputMessage =>
      '[Ţĥé àððŕéšš öŕ þàţĥ îš ñöţ ṽàļîð.~~~~~~~~~~~~~~]';

  @override
  String get connErrorInvalidInputHint =>
      '[Éñţéŕ àñ àððŕéšš ļîķé ĥţţþš://ĥöšţ:þöŕţ ŵîţĥöüţ à üšéŕñàɱé, þàššŵöŕð öŕ ķéý, àñð à þàţĥ ţĥàţ šţàŕţš ŵîţĥ à šļàšĥ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get appTitle => '[Çöñšöļàŕŕ~~~~]';
}
