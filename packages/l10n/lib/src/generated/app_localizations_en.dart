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

  @override
  String get sonarrTitle => 'Series';

  @override
  String get sonarrSwitchToListTooltip => 'Show as list';

  @override
  String get sonarrSwitchToGridTooltip => 'Show as grid';

  @override
  String get sonarrLoadingLabel => 'Loading series';

  @override
  String get sonarrRetry => 'Try again';

  @override
  String get sonarrEmptyHeadline => 'No series yet';

  @override
  String get sonarrEmptyMessage =>
      'Series you add in Sonarr will show up here.';

  @override
  String get sonarrEmptyAction => 'Refresh';

  @override
  String get sonarrNoServerHeadline => 'No Sonarr server';

  @override
  String get sonarrNoServerMessage =>
      'Add your Sonarr server to browse your series.';

  @override
  String get sonarrNoServerAction => 'Add a server';

  @override
  String get sonarrOpenServers => 'Check server settings';

  @override
  String get sonarrErrorTitle => 'Couldn\'t load your series';

  @override
  String get sonarrErrorAuthTitle => 'Sonarr rejected the sign-in';

  @override
  String get sonarrErrorVersionTitle => 'Unsupported Sonarr version';

  @override
  String get sonarrErrorAuthMessage =>
      'The API key or password was not accepted.';

  @override
  String get sonarrErrorAuthHint =>
      'Check the credentials in the server settings.';

  @override
  String get sonarrErrorNeedsCredentialsMessage =>
      'The saved credentials for this server are missing.';

  @override
  String get sonarrErrorNeedsCredentialsHint =>
      'Enter the API key or password again in the server settings.';

  @override
  String get sonarrErrorNetworkMessage => 'Sonarr could not be reached.';

  @override
  String get sonarrErrorNetworkHint =>
      'Check that you are on the right network and that the address and port are correct.';

  @override
  String get sonarrErrorTimeoutMessage => 'Sonarr took too long to answer.';

  @override
  String get sonarrErrorTimeoutHint =>
      'Try again in a moment, or check that the server is running and not overloaded.';

  @override
  String get sonarrErrorVersionMessage =>
      'This Sonarr version is too old for Consolarr.';

  @override
  String get sonarrErrorVersionHint => 'Update Sonarr to version 3 or newer.';

  @override
  String get sonarrErrorServerMessage => 'Sonarr reported an internal problem.';

  @override
  String get sonarrErrorServerHint => 'Check the Sonarr logs, then try again.';

  @override
  String get sonarrErrorParseMessage =>
      'Sonarr sent an answer the app could not read.';

  @override
  String get sonarrErrorParseHint =>
      'Make sure the address points to Sonarr and not to another service.';

  @override
  String get sonarrErrorNotFoundMessage => 'Nothing answered at this address.';

  @override
  String get sonarrErrorNotFoundHint =>
      'Check the address and the path prefix, for example /sonarr behind a reverse proxy.';

  @override
  String get sonarrErrorTlsMessage =>
      'The server\'s certificate is not trusted.';

  @override
  String get sonarrErrorTlsHint =>
      'Review the certificate in the server settings before trusting it.';

  @override
  String get sonarrErrorCleartextMessage =>
      'This server uses plain http, which is not allowed.';

  @override
  String get sonarrErrorCleartextHint =>
      'Use https, or allow plain http for this server in its settings.';

  @override
  String get sonarrErrorGenericMessage =>
      'Something went wrong while talking to Sonarr.';

  @override
  String get sonarrErrorGenericHint =>
      'Try again, and check the server settings if it keeps happening.';

  @override
  String get sonarrOfflineMessage => 'Offline. Showing your saved series.';

  @override
  String sonarrUpdatedAgo(String age) {
    return 'Updated $age';
  }

  @override
  String get sonarrAgeJustNow => 'just now';

  @override
  String sonarrAgeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String sonarrAgeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String sonarrAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get sonarrStatusContinuing => 'Continuing';

  @override
  String get sonarrStatusEnded => 'Ended';

  @override
  String get sonarrStatusUpcoming => 'Upcoming';

  @override
  String get sonarrStatusDeleted => 'Deleted';

  @override
  String get sonarrMonitored => 'Monitored';

  @override
  String get sonarrUnmonitored => 'Unmonitored';

  @override
  String sonarrEpisodesShort(int have, int total) {
    return '$have/$total';
  }

  @override
  String sonarrEpisodesProgress(int have, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$have/$total episodes',
      one: '$have/1 episode',
    );
    return '$_temp0';
  }

  @override
  String sonarrSeasonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seasons',
      one: '1 season',
    );
    return '$_temp0';
  }

  @override
  String sonarrSizeMb(String size) {
    return '$size MB';
  }

  @override
  String sonarrSizeGb(String size) {
    return '$size GB';
  }

  @override
  String sonarrSizeTb(String size) {
    return '$size TB';
  }

  @override
  String get sonarrNextAiringToday => 'Airs today';

  @override
  String get sonarrNextAiringTomorrow => 'Airs tomorrow';

  @override
  String sonarrNextAiringInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Airs in $days days',
      one: 'Airs in 1 day',
    );
    return '$_temp0';
  }

  @override
  String sonarrSeriesSemantics(String title, String details) {
    return '$title, $details';
  }

  @override
  String get torrentsTitle => 'Torrents';

  @override
  String torCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count torrents',
      one: '1 torrent',
      zero: 'No torrents',
    );
    return '$_temp0';
  }

  @override
  String get torSpeedDown => 'Download';

  @override
  String get torSpeedUp => 'Upload';

  @override
  String get torSpeedIdle => 'Idle';

  @override
  String get torSpeedPartial => 'Speed information is unavailable right now.';

  @override
  String get torSpeedOffline => 'Offline';

  @override
  String torSpeedHeaderSemantics(String down, String up, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count torrents',
      one: '1 torrent',
      zero: 'no torrents',
    );
    return 'Download $down, upload $up, $_temp0';
  }

  @override
  String get torStateDownloading => 'Downloading';

  @override
  String get torStateStalled => 'Stalled';

  @override
  String get torStateChecking => 'Checking';

  @override
  String get torStateQueued => 'Queued';

  @override
  String get torStateSeeding => 'Seeding';

  @override
  String get torStatePaused => 'Paused';

  @override
  String get torStateFinished => 'Finished';

  @override
  String get torStateError => 'Error';

  @override
  String get torStateUnknown => 'Unknown';

  @override
  String torProgressPercent(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString';
  }

  @override
  String torRowSemantics(String name, String state, String percent) {
    return '$name, $state, $percent complete';
  }

  @override
  String torDetailSize(String size) {
    return '$size';
  }

  @override
  String torDetailDown(String speed) {
    return 'Down $speed';
  }

  @override
  String torDetailUp(String speed) {
    return 'Up $speed';
  }

  @override
  String torDetailEta(String time) {
    return '$time left';
  }

  @override
  String torDetailRatio(double ratio) {
    final intl.NumberFormat ratioNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String ratioString = ratioNumberFormat.format(ratio);

    return 'Ratio $ratioString';
  }

  @override
  String torSpeedPerSecond(String size) {
    return '$size/s';
  }

  @override
  String torUnitB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString B';
  }

  @override
  String torUnitKB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString KB';
  }

  @override
  String torUnitMB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString MB';
  }

  @override
  String torUnitGB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString GB';
  }

  @override
  String torUnitTB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '$valueString TB';
  }

  @override
  String torDurationSeconds(int count) {
    return '${count}s';
  }

  @override
  String torDurationMinutes(int count) {
    return '${count}m';
  }

  @override
  String torDurationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String torDurationDaysHours(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String get torEmptyHeadline => 'No torrents yet';

  @override
  String get torEmptyMessage =>
      'Torrents you add in your client will show up here.';

  @override
  String get torNoServerHeadline => 'No torrent client yet';

  @override
  String get torNoServerMessage =>
      'Add a qBittorrent server to see your torrents.';

  @override
  String get torNoServerAction => 'Add a server';

  @override
  String get torErrorHeadline => 'Can\'t load torrents';

  @override
  String get torRetry => 'Try again';

  @override
  String get torOfflineMessage =>
      'Can\'t reach the server. Showing the last data.';

  @override
  String torOfflineAge(String time) {
    return 'Updated $time ago';
  }

  @override
  String get torOfflineJustNow => 'Updated just now';

  @override
  String get torReconnect => 'Reconnect';

  @override
  String get torSpeedLimitsHint => 'Open speed limits';
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

  @override
  String get sonarrTitle => '[Šéŕîéš~~~]';

  @override
  String get sonarrSwitchToListTooltip => '[Šĥöŵ àš ļîšţ~~~~~]';

  @override
  String get sonarrSwitchToGridTooltip => '[Šĥöŵ àš ĝŕîð~~~~~]';

  @override
  String get sonarrLoadingLabel => '[Ļöàðîñĝ šéŕîéš~~~~~~]';

  @override
  String get sonarrRetry => '[Ţŕý àĝàîñ~~~~]';

  @override
  String get sonarrEmptyHeadline => '[Ñö šéŕîéš ýéţ~~~~~~]';

  @override
  String get sonarrEmptyMessage =>
      '[Šéŕîéš ýöü àðð îñ Šöñàŕŕ ŵîļļ šĥöŵ üþ ĥéŕé.~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrEmptyAction => '[Ŕéƒŕéšĥ~~~]';

  @override
  String get sonarrNoServerHeadline => '[Ñö Šöñàŕŕ šéŕṽéŕ~~~~~~~]';

  @override
  String get sonarrNoServerMessage =>
      '[Àðð ýöüŕ Šöñàŕŕ šéŕṽéŕ ţö ƀŕöŵšé ýöüŕ šéŕîéš.~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrNoServerAction => '[Àðð à šéŕṽéŕ~~~~~]';

  @override
  String get sonarrOpenServers => '[Çĥéçķ šéŕṽéŕ šéţţîñĝš~~~~~~~~~]';

  @override
  String get sonarrErrorTitle => '[Çöüļðñ\'ţ ļöàð ýöüŕ šéŕîéš~~~~~~~~~~]';

  @override
  String get sonarrErrorAuthTitle => '[Šöñàŕŕ ŕéĵéçţéð ţĥé šîĝñ-îñ~~~~~~~~~~~]';

  @override
  String get sonarrErrorVersionTitle =>
      '[Üñšüþþöŕţéð Šöñàŕŕ ṽéŕšîöñ~~~~~~~~~~~]';

  @override
  String get sonarrErrorAuthMessage =>
      '[Ţĥé ÀÞÎ ķéý öŕ þàššŵöŕð ŵàš ñöţ àççéþţéð.~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorAuthHint =>
      '[Çĥéçķ ţĥé çŕéðéñţîàļš îñ ţĥé šéŕṽéŕ šéţţîñĝš.~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorNeedsCredentialsMessage =>
      '[Ţĥé šàṽéð çŕéðéñţîàļš ƒöŕ ţĥîš šéŕṽéŕ àŕé ɱîššîñĝ.~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorNeedsCredentialsHint =>
      '[Éñţéŕ ţĥé ÀÞÎ ķéý öŕ þàššŵöŕð àĝàîñ îñ ţĥé šéŕṽéŕ šéţţîñĝš.~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorNetworkMessage =>
      '[Šöñàŕŕ çöüļð ñöţ ƀé ŕéàçĥéð.~~~~~~~~~~~~]';

  @override
  String get sonarrErrorNetworkHint =>
      '[Çĥéçķ ţĥàţ ýöü àŕé öñ ţĥé ŕîĝĥţ ñéţŵöŕķ àñð ţĥàţ ţĥé àððŕéšš àñð þöŕţ àŕé çöŕŕéçţ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorTimeoutMessage =>
      '[Šöñàŕŕ ţööķ ţöö ļöñĝ ţö àñšŵéŕ.~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorTimeoutHint =>
      '[Ţŕý àĝàîñ îñ à ɱöɱéñţ, öŕ çĥéçķ ţĥàţ ţĥé šéŕṽéŕ îš ŕüññîñĝ àñð ñöţ öṽéŕļöàðéð.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorVersionMessage =>
      '[Ţĥîš Šöñàŕŕ ṽéŕšîöñ îš ţöö öļð ƒöŕ Çöñšöļàŕŕ.~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorVersionHint =>
      '[Üþðàţé Šöñàŕŕ ţö ṽéŕšîöñ 3 öŕ ñéŵéŕ.~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorServerMessage =>
      '[Šöñàŕŕ ŕéþöŕţéð àñ îñţéŕñàļ þŕöƀļéɱ.~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorServerHint =>
      '[Çĥéçķ ţĥé Šöñàŕŕ ļöĝš, ţĥéñ ţŕý àĝàîñ.~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorParseMessage =>
      '[Šöñàŕŕ šéñţ àñ àñšŵéŕ ţĥé àþþ çöüļð ñöţ ŕéàð.~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorParseHint =>
      '[Ṁàķé šüŕé ţĥé àððŕéšš þöîñţš ţö Šöñàŕŕ àñð ñöţ ţö àñöţĥéŕ šéŕṽîçé.~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorNotFoundMessage =>
      '[Ñöţĥîñĝ àñšŵéŕéð àţ ţĥîš àððŕéšš.~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorNotFoundHint =>
      '[Çĥéçķ ţĥé àððŕéšš àñð ţĥé þàţĥ þŕéƒîẋ, ƒöŕ éẋàɱþļé /šöñàŕŕ ƀéĥîñð à ŕéṽéŕšé þŕöẋý.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorTlsMessage =>
      '[Ţĥé šéŕṽéŕ\'š çéŕţîƒîçàţé îš ñöţ ţŕüšţéð.~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorTlsHint =>
      '[Ŕéṽîéŵ ţĥé çéŕţîƒîçàţé îñ ţĥé šéŕṽéŕ šéţţîñĝš ƀéƒöŕé ţŕüšţîñĝ îţ.~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorCleartextMessage =>
      '[Ţĥîš šéŕṽéŕ üšéš þļàîñ ĥţţþ, ŵĥîçĥ îš ñöţ àļļöŵéð.~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorCleartextHint =>
      '[Üšé ĥţţþš, öŕ àļļöŵ þļàîñ ĥţţþ ƒöŕ ţĥîš šéŕṽéŕ îñ îţš šéţţîñĝš.~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorGenericMessage =>
      '[Šöɱéţĥîñĝ ŵéñţ ŵŕöñĝ ŵĥîļé ţàļķîñĝ ţö Šöñàŕŕ.~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrErrorGenericHint =>
      '[Ţŕý àĝàîñ, àñð çĥéçķ ţĥé šéŕṽéŕ šéţţîñĝš îƒ îţ ķééþš ĥàþþéñîñĝ.~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get sonarrOfflineMessage =>
      '[Öƒƒļîñé. Šĥöŵîñĝ ýöüŕ šàṽéð šéŕîéš.~~~~~~~~~~~~~~]';

  @override
  String sonarrUpdatedAgo(String age) {
    return '[Üþðàţéð ~~~~$age]';
  }

  @override
  String get sonarrAgeJustNow => '[ĵüšţ ñöŵ~~~~]';

  @override
  String sonarrAgeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ɱîñüţéš àĝö~~~~~',
      one: '1 ɱîñüţé àĝö~~~~~',
    );
    return '$_temp0';
  }

  @override
  String sonarrAgeHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ĥöüŕš àĝö~~~~',
      one: '1 ĥöüŕ àĝö~~~~',
    );
    return '$_temp0';
  }

  @override
  String sonarrAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ðàýš àĝö~~~~',
      one: '1 ðàý àĝö~~~~',
    );
    return '$_temp0';
  }

  @override
  String get sonarrStatusContinuing => '[Çöñţîñüîñĝ~~~~]';

  @override
  String get sonarrStatusEnded => '[Éñðéð~~]';

  @override
  String get sonarrStatusUpcoming => '[Üþçöɱîñĝ~~~~]';

  @override
  String get sonarrStatusDeleted => '[Ðéļéţéð~~~]';

  @override
  String get sonarrMonitored => '[Ṁöñîţöŕéð~~~~]';

  @override
  String get sonarrUnmonitored => '[Üñɱöñîţöŕéð~~~~~]';

  @override
  String sonarrEpisodesShort(int have, int total) {
    return '[$have/~$total]';
  }

  @override
  String sonarrEpisodesProgress(int have, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$have/~$total éþîšöðéš~~~~',
      one: '$have/1 éþîšöðé~~~~',
    );
    return '$_temp0';
  }

  @override
  String sonarrSeasonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count šéàšöñš~~~~',
      one: '1 šéàšöñ~~~~',
    );
    return '$_temp0';
  }

  @override
  String sonarrSizeMb(String size) {
    return '[$size Ṁß~~]';
  }

  @override
  String sonarrSizeGb(String size) {
    return '[$size Ĝß~~]';
  }

  @override
  String sonarrSizeTb(String size) {
    return '[$size Ţß~~]';
  }

  @override
  String get sonarrNextAiringToday => '[Àîŕš ţöðàý~~~~]';

  @override
  String get sonarrNextAiringTomorrow => '[Àîŕš ţöɱöŕŕöŵ~~~~~~]';

  @override
  String sonarrNextAiringInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Àîŕš îñ ~~~~$days ðàýš~~',
      one: 'Àîŕš îñ 1 ðàý~~~~~~',
    );
    return '$_temp0';
  }

  @override
  String sonarrSeriesSemantics(String title, String details) {
    return '[$title, ~$details]';
  }

  @override
  String get torrentsTitle => '[Ţöŕŕéñţš~~~~]';

  @override
  String torCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ţöŕŕéñţš~~~~',
      one: '1 ţöŕŕéñţ~~~~',
      zero: 'Ñö ţöŕŕéñţš~~~~~',
    );
    return '$_temp0';
  }

  @override
  String get torSpeedDown => '[Ðöŵñļöàð~~~~]';

  @override
  String get torSpeedUp => '[Üþļöàð~~~]';

  @override
  String get torSpeedIdle => '[Îðļé~~]';

  @override
  String get torSpeedPartial =>
      '[Šþééð îñƒöŕɱàţîöñ îš üñàṽàîļàƀļé ŕîĝĥţ ñöŵ.~~~~~~~~~~~~~~~~~~]';

  @override
  String get torSpeedOffline => '[Öƒƒļîñé~~~]';

  @override
  String torSpeedHeaderSemantics(String down, String up, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ţöŕŕéñţš~~~~',
      one: '1 ţöŕŕéñţ~~~~',
      zero: 'ñö ţöŕŕéñţš~~~~~',
    );
    return 'Ðöŵñļöàð ~~~~$down, üþļöàð ~~~~$up, ~$_temp0';
  }

  @override
  String get torStateDownloading => '[Ðöŵñļöàðîñĝ~~~~~]';

  @override
  String get torStateStalled => '[Šţàļļéð~~~]';

  @override
  String get torStateChecking => '[Çĥéçķîñĝ~~~~]';

  @override
  String get torStateQueued => '[Ǫüéüéð~~~]';

  @override
  String get torStateSeeding => '[Šééðîñĝ~~~]';

  @override
  String get torStatePaused => '[Þàüšéð~~~]';

  @override
  String get torStateFinished => '[Ƒîñîšĥéð~~~~]';

  @override
  String get torStateError => '[Éŕŕöŕ~~]';

  @override
  String get torStateUnknown => '[Üñķñöŵñ~~~]';

  @override
  String torProgressPercent(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '[$valueString]';
  }

  @override
  String torRowSemantics(String name, String state, String percent) {
    return '[$name, ~$state, ~$percent çöɱþļéţé~~~~]';
  }

  @override
  String torDetailSize(String size) {
    return '[$size]';
  }

  @override
  String torDetailDown(String speed) {
    return '[Ðöŵñ ~~$speed]';
  }

  @override
  String torDetailUp(String speed) {
    return '[Üþ ~~$speed]';
  }

  @override
  String torDetailEta(String time) {
    return '[$time ļéƒţ~~]';
  }

  @override
  String torDetailRatio(double ratio) {
    final intl.NumberFormat ratioNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String ratioString = ratioNumberFormat.format(ratio);

    return '[Ŕàţîö ~~~$ratioString]';
  }

  @override
  String torSpeedPerSecond(String size) {
    return '[$size/š~]';
  }

  @override
  String torUnitB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '[$valueString ß~]';
  }

  @override
  String torUnitKB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '[$valueString Ķß~~]';
  }

  @override
  String torUnitMB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '[$valueString Ṁß~~]';
  }

  @override
  String torUnitGB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '[$valueString Ĝß~~]';
  }

  @override
  String torUnitTB(double value) {
    final intl.NumberFormat valueNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String valueString = valueNumberFormat.format(value);

    return '[$valueString Ţß~~]';
  }

  @override
  String torDurationSeconds(int count) {
    return '[$countš~]';
  }

  @override
  String torDurationMinutes(int count) {
    return '[$countɱ~]';
  }

  @override
  String torDurationHoursMinutes(int hours, int minutes) {
    return '[$hoursĥ ~$minutesɱ~]';
  }

  @override
  String torDurationDaysHours(int days, int hours) {
    return '[$daysð ~$hoursĥ~]';
  }

  @override
  String get torEmptyHeadline => '[Ñö ţöŕŕéñţš ýéţ~~~~~~]';

  @override
  String get torEmptyMessage =>
      '[Ţöŕŕéñţš ýöü àðð îñ ýöüŕ çļîéñţ ŵîļļ šĥöŵ üþ ĥéŕé.~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get torNoServerHeadline => '[Ñö ţöŕŕéñţ çļîéñţ ýéţ~~~~~~~~~]';

  @override
  String get torNoServerMessage =>
      '[Àðð à ǫßîţţöŕŕéñţ šéŕṽéŕ ţö šéé ýöüŕ ţöŕŕéñţš.~~~~~~~~~~~~~~~~~~~]';

  @override
  String get torNoServerAction => '[Àðð à šéŕṽéŕ~~~~~]';

  @override
  String get torErrorHeadline => '[Çàñ\'ţ ļöàð ţöŕŕéñţš~~~~~~~~]';

  @override
  String get torRetry => '[Ţŕý àĝàîñ~~~~]';

  @override
  String get torOfflineMessage =>
      '[Çàñ\'ţ ŕéàçĥ ţĥé šéŕṽéŕ. Šĥöŵîñĝ ţĥé ļàšţ ðàţà.~~~~~~~~~~~~~~~~~~~]';

  @override
  String torOfflineAge(String time) {
    return '[Üþðàţéð ~~~~$time àĝö~~]';
  }

  @override
  String get torOfflineJustNow => '[Üþðàţéð ĵüšţ ñöŵ~~~~~~~]';

  @override
  String get torReconnect => '[Ŕéçöññéçţ~~~~]';

  @override
  String get torSpeedLimitsHint => '[Öþéñ šþééð ļîɱîţš~~~~~~~]';
}
