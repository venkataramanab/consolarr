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
      'Add a media server or download client to get started.';

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
  String get serversTitle => 'Servers';

  @override
  String get serversAddTooltip => 'Add a server';

  @override
  String get serversEmptyHeadline => 'No servers yet';

  @override
  String get serversEmptyMessage =>
      'Add Sonarr or qBittorrent to browse your library and downloads from here.';

  @override
  String get serversEmptyAction => 'Add your first server';

  @override
  String get serversLoadErrorHeadline => 'Couldn\'t load your servers';

  @override
  String get serversLoadErrorMessage =>
      'The saved servers could not be read from this device.';

  @override
  String get serversRetry => 'Try again';

  @override
  String get serversCancel => 'Cancel';

  @override
  String get serverKindSonarr => 'Sonarr';

  @override
  String get serverKindRadarr => 'Radarr';

  @override
  String get serverKindQbittorrent => 'qBittorrent';

  @override
  String get serverKindTransmission => 'Transmission';

  @override
  String get serverKindDeluge => 'Deluge';

  @override
  String get serverKindSonarrDescription => 'TV series library';

  @override
  String get serverKindQbittorrentDescription => 'Torrent downloads';

  @override
  String get serverKindOtherDescription => 'Not available yet';

  @override
  String get serverHealthChecking => 'Checking…';

  @override
  String get serverHealthHealthy => 'Online';

  @override
  String get serverHealthDegraded => 'Responding with problems';

  @override
  String get serverHealthUnauthorized => 'Sign-in failed';

  @override
  String get serverHealthUnreachable => 'Unreachable';

  @override
  String get serverHealthUnknown => 'Couldn\'t check';

  @override
  String get serverBadgeCleartext => 'Plain http';

  @override
  String get serverBadgeNeedsCredentials => 'Needs credentials';

  @override
  String get serverBadgeActive => 'Active';

  @override
  String get serverBadgeStartup => 'Opens at launch';

  @override
  String serverMenuTooltip(String name) {
    return 'More actions for $name';
  }

  @override
  String serverDragHandleLabel(String name) {
    return 'Reorder $name';
  }

  @override
  String get serverActionEdit => 'Edit';

  @override
  String get serverActionSetActive => 'Make active';

  @override
  String get serverActionSetStartup => 'Open at launch';

  @override
  String get serverActionClearStartup => 'Don\'t open at launch';

  @override
  String get serverActionMoveUp => 'Move up';

  @override
  String get serverActionMoveDown => 'Move down';

  @override
  String get serverActionDelete => 'Delete';

  @override
  String serverDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get serverDeleteBody =>
      'This removes the saved credentials, the trusted certificate and the cached data for this server from this device. The server itself is not changed.';

  @override
  String get serverDeleteConfirm => 'Delete';

  @override
  String get serverEditorTitleNew => 'Add server';

  @override
  String get serverEditorTitleEdit => 'Edit server';

  @override
  String get serverEditorSave => 'Save';

  @override
  String get serverSaveFailedHeadline => 'Couldn\'t save the server';

  @override
  String get serverSectionService => 'Service';

  @override
  String get serverSectionAddress => 'Address';

  @override
  String get serverSectionAuth => 'Authentication';

  @override
  String get serverSectionHeaders => 'Custom headers';

  @override
  String get serverSectionSecurity => 'Security';

  @override
  String get serverFieldName => 'Display name';

  @override
  String get serverFieldAddress => 'Address';

  @override
  String get serverFieldAddressHint => 'https://host.example:8989';

  @override
  String get serverFieldPathPrefix => 'Path prefix (optional)';

  @override
  String get serverPathPrefixHelper =>
      'Only needed if a reverse proxy serves the app under a path, for example /sonarr.';

  @override
  String get serverAuthNone => 'None';

  @override
  String get serverAuthApiKey => 'API key';

  @override
  String get serverAuthBasic => 'Username and password';

  @override
  String get serverFieldApiKey => 'API key';

  @override
  String get serverFieldUsername => 'Username';

  @override
  String get serverFieldPassword => 'Password';

  @override
  String get serverSecretKeepHint => 'Leave empty to keep the saved value.';

  @override
  String get serverSecretShow => 'Show value';

  @override
  String get serverSecretHide => 'Hide value';

  @override
  String get serverHeadersHelper =>
      'For reverse-proxy gateways. Values are stored securely on this device.';

  @override
  String get serverHeaderName => 'Header name';

  @override
  String get serverHeaderValue => 'Header value';

  @override
  String get serverHeaderAdd => 'Add header';

  @override
  String get serverHeaderRemove => 'Remove header';

  @override
  String get serverCleartextTitle => 'Allow plain http';

  @override
  String get serverCleartextRisk =>
      'Plain http sends your API key, password and every response without encryption, so anyone on the network can read them. Only allow it on a network you trust, such as your home network.';

  @override
  String get serverCleartextNeeded =>
      'This address uses http. Turn on plain http, or use an https address.';

  @override
  String get serverErrorNameRequired => 'Enter a name for this server.';

  @override
  String get serverErrorAddressRequired => 'Enter the server address.';

  @override
  String get serverErrorAddressInvalid =>
      'Enter a full address such as https://host.example:8989.';

  @override
  String get serverErrorAddressCredentials =>
      'Don\'t put a username or password in the address. Use the fields below.';

  @override
  String get serverErrorAddressQuery =>
      'Remove everything after the ? in the address. Keys belong in the key field.';

  @override
  String get serverErrorAddressPort =>
      'The port must be a number from 1 to 65535.';

  @override
  String get serverErrorAddressNonAscii =>
      'Use the ASCII form of the host name (for example xn--...), not special characters.';

  @override
  String get serverErrorSecretsReenter =>
      'You changed the server address. Enter the key or password again; stored secrets are never sent to a different address.';

  @override
  String get serverSecretReenterHint =>
      'You changed the server address, so the stored key or password will not be used. Enter it again.';

  @override
  String get serverErrorPrefixInvalid =>
      'Use a path such as /sonarr, without spaces, ? or ...';

  @override
  String get serverErrorHeaderInvalid =>
      'Header names may use letters, digits and - _ . only, and must be unique.';

  @override
  String get serverTestButton => 'Test connection';

  @override
  String get serverTestTesting => 'Testing…';

  @override
  String serverTestSuccess(String version) {
    return 'Connected. Server version $version.';
  }

  @override
  String get serverTestSuccessLabel => 'Connected';

  @override
  String get serverTestFailedLabel => 'Failed';

  @override
  String get serverPinTitle => 'Trusted certificate';

  @override
  String get serverPinFingerprint => 'SHA-256 fingerprint';

  @override
  String get serverPinRemove => 'Remove trusted certificate';

  @override
  String get serverPinRemoveTitle => 'Remove trusted certificate?';

  @override
  String get serverPinRemoveBody =>
      'The next connection will ask you to review the server\'s certificate again.';

  @override
  String get serverPinRemoveConfirm => 'Remove';

  @override
  String get serverNeedsCredentialsBanner =>
      'The saved credentials for this server are missing. Enter them again and save.';

  @override
  String get serverDiscardTitle => 'Discard changes?';

  @override
  String get serverDiscardBody =>
      'Your changes to this server haven\'t been saved.';

  @override
  String get serverDiscardConfirm => 'Discard';

  @override
  String get serverDiscardKeep => 'Keep editing';

  @override
  String get certSheetTitleFirstUse => 'Trust this certificate?';

  @override
  String get certSheetExplanationFirstUse =>
      'This server uses a certificate your device doesn\'t recognise. Compare the fingerprint with the one on your server before trusting it.';

  @override
  String get certSheetTitleMismatch => 'Certificate changed';

  @override
  String get certSheetExplanationMismatch =>
      'This server now presents a different certificate than the one you trusted. Connections stay blocked until you decide.';

  @override
  String get certSheetMismatchWarning =>
      'If you did not replace the certificate yourself, someone may be intercepting the connection. Do not trust it.';

  @override
  String get certSheetTitleExpired => 'Certificate expired';

  @override
  String get certSheetExplanationExpired =>
      'This server\'s certificate is expired or not valid yet, so it cannot be trusted. Renew it on the server.';

  @override
  String get certSheetFingerprint => 'SHA-256 fingerprint';

  @override
  String get certSheetPreviousFingerprint => 'Previously trusted fingerprint';

  @override
  String get certSheetSubject => 'Subject';

  @override
  String get certSheetIssuer => 'Issuer';

  @override
  String get certSheetValidity => 'Valid';

  @override
  String certSheetValidityRange(String from, String until) {
    return '$from to $until';
  }

  @override
  String get certSheetAccept => 'Trust certificate';

  @override
  String get certSheetAcceptMismatch => 'Trust new certificate';

  @override
  String get certSheetReject => 'Don\'t trust';

  @override
  String get certSheetHandle => 'Drag handle';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Consolarr';

  @override
  String get onboardingWelcomeBody =>
      'Control your self-hosted media services from your phone. Let\'s connect your first server.';

  @override
  String get onboardingStart => 'Get started';

  @override
  String get onboardingSkip => 'Skip for now';

  @override
  String get onboardingChooseTitle => 'Which service?';

  @override
  String get onboardingChooseBody => 'You can add more servers later.';

  @override
  String get onboardingDetailsTitle => 'Server details';

  @override
  String get onboardingTestTitle => 'Test and finish';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingFinish => 'Finish';

  @override
  String onboardingStepOf(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingTestFirst => 'Test the connection before finishing.';

  @override
  String get appTitle => 'Consolarr';

  @override
  String get navHome => 'Home';

  @override
  String get navSonarr => 'Series';

  @override
  String get navTorrents => 'Torrents';

  @override
  String get navServers => 'Servers';

  @override
  String get navSelectedHint => 'Selected';

  @override
  String get switcherTitle => 'Switch server';

  @override
  String get switcherTooltip => 'Switch server';

  @override
  String get switcherActive => 'Active';

  @override
  String get switcherEmpty => 'No servers of this type yet.';

  @override
  String get healthHealthy => 'Online';

  @override
  String get healthChecking => 'Checking';

  @override
  String get healthDegraded => 'Slow or erroring';

  @override
  String get healthUnauthorized => 'Wrong credentials';

  @override
  String get healthUnreachable => 'Offline';

  @override
  String get homeSetupCta => 'Set up a server';

  @override
  String get homeServicesHeading => 'Your services';

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
  String sonarrSizeMb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString MB';
  }

  @override
  String sonarrSizeGb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString GB';
  }

  @override
  String sonarrSizeTb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '$sizeString TB';
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
      '[Àðð à ɱéðîà šéŕṽéŕ öŕ ðöŵñļöàð çļîéñţ ţö ĝéţ šţàŕţéð.~~~~~~~~~~~~~~~~~~~~~~]';

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
  String get serversTitle => '[Šéŕṽéŕš~~~]';

  @override
  String get serversAddTooltip => '[Àðð à šéŕṽéŕ~~~~~]';

  @override
  String get serversEmptyHeadline => '[Ñö šéŕṽéŕš ýéţ~~~~~~]';

  @override
  String get serversEmptyMessage =>
      '[Àðð Šöñàŕŕ öŕ ǫßîţţöŕŕéñţ ţö ƀŕöŵšé ýöüŕ ļîƀŕàŕý àñð ðöŵñļöàðš ƒŕöɱ ĥéŕé.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serversEmptyAction => '[Àðð ýöüŕ ƒîŕšţ šéŕṽéŕ~~~~~~~~~]';

  @override
  String get serversLoadErrorHeadline =>
      '[Çöüļðñ\'ţ ļöàð ýöüŕ šéŕṽéŕš~~~~~~~~~~~]';

  @override
  String get serversLoadErrorMessage =>
      '[Ţĥé šàṽéð šéŕṽéŕš çöüļð ñöţ ƀé ŕéàð ƒŕöɱ ţĥîš ðéṽîçé.~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serversRetry => '[Ţŕý àĝàîñ~~~~]';

  @override
  String get serversCancel => '[Çàñçéļ~~~]';

  @override
  String get serverKindSonarr => '[Šöñàŕŕ~~~]';

  @override
  String get serverKindRadarr => '[Ŕàðàŕŕ~~~]';

  @override
  String get serverKindQbittorrent => '[ǫßîţţöŕŕéñţ~~~~~]';

  @override
  String get serverKindTransmission => '[Ţŕàñšɱîššîöñ~~~~~]';

  @override
  String get serverKindDeluge => '[Ðéļüĝé~~~]';

  @override
  String get serverKindSonarrDescription => '[ŢṼ šéŕîéš ļîƀŕàŕý~~~~~~~]';

  @override
  String get serverKindQbittorrentDescription => '[Ţöŕŕéñţ ðöŵñļöàðš~~~~~~~]';

  @override
  String get serverKindOtherDescription => '[Ñöţ àṽàîļàƀļé ýéţ~~~~~~~]';

  @override
  String get serverHealthChecking => '[Çĥéçķîñĝ…~~~~]';

  @override
  String get serverHealthHealthy => '[Öñļîñé~~~]';

  @override
  String get serverHealthDegraded => '[Ŕéšþöñðîñĝ ŵîţĥ þŕöƀļéɱš~~~~~~~~~~]';

  @override
  String get serverHealthUnauthorized => '[Šîĝñ-îñ ƒàîļéð~~~~~~]';

  @override
  String get serverHealthUnreachable => '[Üñŕéàçĥàƀļé~~~~~]';

  @override
  String get serverHealthUnknown => '[Çöüļðñ\'ţ çĥéçķ~~~~~~]';

  @override
  String get serverBadgeCleartext => '[Þļàîñ ĥţţþ~~~~]';

  @override
  String get serverBadgeNeedsCredentials => '[Ñééðš çŕéðéñţîàļš~~~~~~~]';

  @override
  String get serverBadgeActive => '[Àçţîṽé~~~]';

  @override
  String get serverBadgeStartup => '[Öþéñš àţ ļàüñçĥ~~~~~~]';

  @override
  String serverMenuTooltip(String name) {
    return '[Ṁöŕé àçţîöñš ƒöŕ ~~~~~~~$name]';
  }

  @override
  String serverDragHandleLabel(String name) {
    return '[Ŕéöŕðéŕ ~~~~$name]';
  }

  @override
  String get serverActionEdit => '[Éðîţ~~]';

  @override
  String get serverActionSetActive => '[Ṁàķé àçţîṽé~~~~~]';

  @override
  String get serverActionSetStartup => '[Öþéñ àţ ļàüñçĥ~~~~~~]';

  @override
  String get serverActionClearStartup => '[Ðöñ\'ţ öþéñ àţ ļàüñçĥ~~~~~~~~]';

  @override
  String get serverActionMoveUp => '[Ṁöṽé üþ~~~]';

  @override
  String get serverActionMoveDown => '[Ṁöṽé ðöŵñ~~~~]';

  @override
  String get serverActionDelete => '[Ðéļéţé~~~]';

  @override
  String serverDeleteTitle(String name) {
    return '[Ðéļéţé ~~~$name?~]';
  }

  @override
  String get serverDeleteBody =>
      '[Ţĥîš ŕéɱöṽéš ţĥé šàṽéð çŕéðéñţîàļš, ţĥé ţŕüšţéð çéŕţîƒîçàţé àñð ţĥé çàçĥéð ðàţà ƒöŕ ţĥîš šéŕṽéŕ ƒŕöɱ ţĥîš ðéṽîçé. Ţĥé šéŕṽéŕ îţšéļƒ îš ñöţ çĥàñĝéð.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverDeleteConfirm => '[Ðéļéţé~~~]';

  @override
  String get serverEditorTitleNew => '[Àðð šéŕṽéŕ~~~~]';

  @override
  String get serverEditorTitleEdit => '[Éðîţ šéŕṽéŕ~~~~~]';

  @override
  String get serverEditorSave => '[Šàṽé~~]';

  @override
  String get serverSaveFailedHeadline =>
      '[Çöüļðñ\'ţ šàṽé ţĥé šéŕṽéŕ~~~~~~~~~~]';

  @override
  String get serverSectionService => '[Šéŕṽîçé~~~]';

  @override
  String get serverSectionAddress => '[Àððŕéšš~~~]';

  @override
  String get serverSectionAuth => '[Àüţĥéñţîçàţîöñ~~~~~~]';

  @override
  String get serverSectionHeaders => '[Çüšţöɱ ĥéàðéŕš~~~~~~]';

  @override
  String get serverSectionSecurity => '[Šéçüŕîţý~~~~]';

  @override
  String get serverFieldName => '[Ðîšþļàý ñàɱé~~~~~]';

  @override
  String get serverFieldAddress => '[Àððŕéšš~~~]';

  @override
  String get serverFieldAddressHint => '[ĥţţþš://ĥöšţ.éẋàɱþļé:8989~~~~~~~~~~]';

  @override
  String get serverFieldPathPrefix => '[Þàţĥ þŕéƒîẋ (öþţîöñàļ)~~~~~~~~~]';

  @override
  String get serverPathPrefixHelper =>
      '[Öñļý ñééðéð îƒ à ŕéṽéŕšé þŕöẋý šéŕṽéš ţĥé àþþ üñðéŕ à þàţĥ, ƒöŕ éẋàɱþļé /šöñàŕŕ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverAuthNone => '[Ñöñé~~]';

  @override
  String get serverAuthApiKey => '[ÀÞÎ ķéý~~~]';

  @override
  String get serverAuthBasic => '[Üšéŕñàɱé àñð þàššŵöŕð~~~~~~~~~]';

  @override
  String get serverFieldApiKey => '[ÀÞÎ ķéý~~~]';

  @override
  String get serverFieldUsername => '[Üšéŕñàɱé~~~~]';

  @override
  String get serverFieldPassword => '[Þàššŵöŕð~~~~]';

  @override
  String get serverSecretKeepHint =>
      '[Ļéàṽé éɱþţý ţö ķééþ ţĥé šàṽéð ṽàļüé.~~~~~~~~~~~~~~~]';

  @override
  String get serverSecretShow => '[Šĥöŵ ṽàļüé~~~~]';

  @override
  String get serverSecretHide => '[Ĥîðé ṽàļüé~~~~]';

  @override
  String get serverHeadersHelper =>
      '[Ƒöŕ ŕéṽéŕšé-þŕöẋý ĝàţéŵàýš. Ṽàļüéš àŕé šţöŕéð šéçüŕéļý öñ ţĥîš ðéṽîçé.~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverHeaderName => '[Ĥéàðéŕ ñàɱé~~~~~]';

  @override
  String get serverHeaderValue => '[Ĥéàðéŕ ṽàļüé~~~~~]';

  @override
  String get serverHeaderAdd => '[Àðð ĥéàðéŕ~~~~]';

  @override
  String get serverHeaderRemove => '[Ŕéɱöṽé ĥéàðéŕ~~~~~~]';

  @override
  String get serverCleartextTitle => '[Àļļöŵ þļàîñ ĥţţþ~~~~~~~]';

  @override
  String get serverCleartextRisk =>
      '[Þļàîñ ĥţţþ šéñðš ýöüŕ ÀÞÎ ķéý, þàššŵöŕð àñð éṽéŕý ŕéšþöñšé ŵîţĥöüţ éñçŕýþţîöñ, šö àñýöñé öñ ţĥé ñéţŵöŕķ çàñ ŕéàð ţĥéɱ. Öñļý àļļöŵ îţ öñ à ñéţŵöŕķ ýöü ţŕüšţ, šüçĥ àš ýöüŕ ĥöɱé ñéţŵöŕķ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverCleartextNeeded =>
      '[Ţĥîš àððŕéšš üšéš ĥţţþ. Ţüŕñ öñ þļàîñ ĥţţþ, öŕ üšé àñ ĥţţþš àððŕéšš.~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorNameRequired =>
      '[Éñţéŕ à ñàɱé ƒöŕ ţĥîš šéŕṽéŕ.~~~~~~~~~~~~]';

  @override
  String get serverErrorAddressRequired =>
      '[Éñţéŕ ţĥé šéŕṽéŕ àððŕéšš.~~~~~~~~~~]';

  @override
  String get serverErrorAddressInvalid =>
      '[Éñţéŕ à ƒüļļ àððŕéšš šüçĥ àš ĥţţþš://ĥöšţ.éẋàɱþļé:8989.~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorAddressCredentials =>
      '[Ðöñ\'ţ þüţ à üšéŕñàɱé öŕ þàššŵöŕð îñ ţĥé àððŕéšš. Üšé ţĥé ƒîéļðš ƀéļöŵ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorAddressQuery =>
      '[Ŕéɱöṽé éṽéŕýţĥîñĝ àƒţéŕ ţĥé ? îñ ţĥé àððŕéšš. Ķéýš ƀéļöñĝ îñ ţĥé ķéý ƒîéļð.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorAddressPort =>
      '[Ţĥé þöŕţ ɱüšţ ƀé à ñüɱƀéŕ ƒŕöɱ 1 ţö 65535.~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorAddressNonAscii =>
      '[Üšé ţĥé ÀŠÇÎÎ ƒöŕɱ öƒ ţĥé ĥöšţ ñàɱé (ƒöŕ éẋàɱþļé ẋñ--...), ñöţ šþéçîàļ çĥàŕàçţéŕš.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorSecretsReenter =>
      '[Ýöü çĥàñĝéð ţĥé šéŕṽéŕ àððŕéšš. Éñţéŕ ţĥé ķéý öŕ þàššŵöŕð àĝàîñ; šţöŕéð šéçŕéţš àŕé ñéṽéŕ šéñţ ţö à ðîƒƒéŕéñţ àððŕéšš.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverSecretReenterHint =>
      '[Ýöü çĥàñĝéð ţĥé šéŕṽéŕ àððŕéšš, šö ţĥé šţöŕéð ķéý öŕ þàššŵöŕð ŵîļļ ñöţ ƀé üšéð. Éñţéŕ îţ àĝàîñ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorPrefixInvalid =>
      '[Üšé à þàţĥ šüçĥ àš /šöñàŕŕ, ŵîţĥöüţ šþàçéš, ? öŕ ...~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverErrorHeaderInvalid =>
      '[Ĥéàðéŕ ñàɱéš ɱàý üšé ļéţţéŕš, ðîĝîţš àñð - _ . öñļý, àñð ɱüšţ ƀé üñîǫüé.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverTestButton => '[Ţéšţ çöññéçţîöñ~~~~~~]';

  @override
  String get serverTestTesting => '[Ţéšţîñĝ…~~~~]';

  @override
  String serverTestSuccess(String version) {
    return '[Çöññéçţéð. Šéŕṽéŕ ṽéŕšîöñ ~~~~~~~~~~~$version.~]';
  }

  @override
  String get serverTestSuccessLabel => '[Çöññéçţéð~~~~]';

  @override
  String get serverTestFailedLabel => '[Ƒàîļéð~~~]';

  @override
  String get serverPinTitle => '[Ţŕüšţéð çéŕţîƒîçàţé~~~~~~~~]';

  @override
  String get serverPinFingerprint => '[ŠĤÀ-256 ƒîñĝéŕþŕîñţ~~~~~~~~]';

  @override
  String get serverPinRemove => '[Ŕéɱöṽé ţŕüšţéð çéŕţîƒîçàţé~~~~~~~~~~~]';

  @override
  String get serverPinRemoveTitle => '[Ŕéɱöṽé ţŕüšţéð çéŕţîƒîçàţé?~~~~~~~~~~~]';

  @override
  String get serverPinRemoveBody =>
      '[Ţĥé ñéẋţ çöññéçţîöñ ŵîļļ àšķ ýöü ţö ŕéṽîéŵ ţĥé šéŕṽéŕ\'š çéŕţîƒîçàţé àĝàîñ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverPinRemoveConfirm => '[Ŕéɱöṽé~~~]';

  @override
  String get serverNeedsCredentialsBanner =>
      '[Ţĥé šàṽéð çŕéðéñţîàļš ƒöŕ ţĥîš šéŕṽéŕ àŕé ɱîššîñĝ. Éñţéŕ ţĥéɱ àĝàîñ àñð šàṽé.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverDiscardTitle => '[Ðîšçàŕð çĥàñĝéš?~~~~~~~]';

  @override
  String get serverDiscardBody =>
      '[Ýöüŕ çĥàñĝéš ţö ţĥîš šéŕṽéŕ ĥàṽéñ\'ţ ƀééñ šàṽéð.~~~~~~~~~~~~~~~~~~~]';

  @override
  String get serverDiscardConfirm => '[Ðîšçàŕð~~~]';

  @override
  String get serverDiscardKeep => '[Ķééþ éðîţîñĝ~~~~~]';

  @override
  String get certSheetTitleFirstUse => '[Ţŕüšţ ţĥîš çéŕţîƒîçàţé?~~~~~~~~~~]';

  @override
  String get certSheetExplanationFirstUse =>
      '[Ţĥîš šéŕṽéŕ üšéš à çéŕţîƒîçàţé ýöüŕ ðéṽîçé ðöéšñ\'ţ ŕéçöĝñîšé. Çöɱþàŕé ţĥé ƒîñĝéŕþŕîñţ ŵîţĥ ţĥé öñé öñ ýöüŕ šéŕṽéŕ ƀéƒöŕé ţŕüšţîñĝ îţ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get certSheetTitleMismatch => '[Çéŕţîƒîçàţé çĥàñĝéð~~~~~~~~]';

  @override
  String get certSheetExplanationMismatch =>
      '[Ţĥîš šéŕṽéŕ ñöŵ þŕéšéñţš à ðîƒƒéŕéñţ çéŕţîƒîçàţé ţĥàñ ţĥé öñé ýöü ţŕüšţéð. Çöññéçţîöñš šţàý ƀļöçķéð üñţîļ ýöü ðéçîðé.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get certSheetMismatchWarning =>
      '[Îƒ ýöü ðîð ñöţ ŕéþļàçé ţĥé çéŕţîƒîçàţé ýöüŕšéļƒ, šöɱéöñé ɱàý ƀé îñţéŕçéþţîñĝ ţĥé çöññéçţîöñ. Ðö ñöţ ţŕüšţ îţ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get certSheetTitleExpired => '[Çéŕţîƒîçàţé éẋþîŕéð~~~~~~~~]';

  @override
  String get certSheetExplanationExpired =>
      '[Ţĥîš šéŕṽéŕ\'š çéŕţîƒîçàţé îš éẋþîŕéð öŕ ñöţ ṽàļîð ýéţ, šö îţ çàññöţ ƀé ţŕüšţéð. Ŕéñéŵ îţ öñ ţĥé šéŕṽéŕ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get certSheetFingerprint => '[ŠĤÀ-256 ƒîñĝéŕþŕîñţ~~~~~~~~]';

  @override
  String get certSheetPreviousFingerprint =>
      '[Þŕéṽîöüšļý ţŕüšţéð ƒîñĝéŕþŕîñţ~~~~~~~~~~~~]';

  @override
  String get certSheetSubject => '[Šüƀĵéçţ~~~]';

  @override
  String get certSheetIssuer => '[Îššüéŕ~~~]';

  @override
  String get certSheetValidity => '[Ṽàļîð~~]';

  @override
  String certSheetValidityRange(String from, String until) {
    return '[$from ţö ~~$until]';
  }

  @override
  String get certSheetAccept => '[Ţŕüšţ çéŕţîƒîçàţé~~~~~~~]';

  @override
  String get certSheetAcceptMismatch => '[Ţŕüšţ ñéŵ çéŕţîƒîçàţé~~~~~~~~~]';

  @override
  String get certSheetReject => '[Ðöñ\'ţ ţŕüšţ~~~~~]';

  @override
  String get certSheetHandle => '[Ðŕàĝ ĥàñðļé~~~~~]';

  @override
  String get onboardingWelcomeTitle => '[Ŵéļçöɱé ţö Çöñšöļàŕŕ~~~~~~~~]';

  @override
  String get onboardingWelcomeBody =>
      '[Çöñţŕöļ ýöüŕ šéļƒ-ĥöšţéð ɱéðîà šéŕṽîçéš ƒŕöɱ ýöüŕ þĥöñé. Ļéţ\'š çöññéçţ ýöüŕ ƒîŕšţ šéŕṽéŕ.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]';

  @override
  String get onboardingStart => '[Ĝéţ šţàŕţéð~~~~~]';

  @override
  String get onboardingSkip => '[Šķîþ ƒöŕ ñöŵ~~~~~]';

  @override
  String get onboardingChooseTitle => '[Ŵĥîçĥ šéŕṽîçé?~~~~~~]';

  @override
  String get onboardingChooseBody =>
      '[Ýöü çàñ àðð ɱöŕé šéŕṽéŕš ļàţéŕ.~~~~~~~~~~~~~]';

  @override
  String get onboardingDetailsTitle => '[Šéŕṽéŕ ðéţàîļš~~~~~~]';

  @override
  String get onboardingTestTitle => '[Ţéšţ àñð ƒîñîšĥ~~~~~~]';

  @override
  String get onboardingNext => '[Ñéẋţ~~]';

  @override
  String get onboardingBack => '[ßàçķ~~]';

  @override
  String get onboardingFinish => '[Ƒîñîšĥ~~~]';

  @override
  String onboardingStepOf(int current, int total) {
    return '[Šţéþ ~~$current öƒ ~~$total]';
  }

  @override
  String get onboardingTestFirst =>
      '[Ţéšţ ţĥé çöññéçţîöñ ƀéƒöŕé ƒîñîšĥîñĝ.~~~~~~~~~~~~~~~]';

  @override
  String get appTitle => '[Çöñšöļàŕŕ~~~~]';

  @override
  String get navHome => '[Ĥöɱé~~]';

  @override
  String get navSonarr => '[Šéŕîéš~~~]';

  @override
  String get navTorrents => '[Ţöŕŕéñţš~~~~]';

  @override
  String get navServers => '[Šéŕṽéŕš~~~]';

  @override
  String get navSelectedHint => '[Šéļéçţéð~~~~]';

  @override
  String get switcherTitle => '[Šŵîţçĥ šéŕṽéŕ~~~~~~]';

  @override
  String get switcherTooltip => '[Šŵîţçĥ šéŕṽéŕ~~~~~~]';

  @override
  String get switcherActive => '[Àçţîṽé~~~]';

  @override
  String get switcherEmpty => '[Ñö šéŕṽéŕš öƒ ţĥîš ţýþé ýéţ.~~~~~~~~~~~~]';

  @override
  String get healthHealthy => '[Öñļîñé~~~]';

  @override
  String get healthChecking => '[Çĥéçķîñĝ~~~~]';

  @override
  String get healthDegraded => '[Šļöŵ öŕ éŕŕöŕîñĝ~~~~~~~]';

  @override
  String get healthUnauthorized => '[Ŵŕöñĝ çŕéðéñţîàļš~~~~~~~]';

  @override
  String get healthUnreachable => '[Öƒƒļîñé~~~]';

  @override
  String get homeSetupCta => '[Šéţ üþ à šéŕṽéŕ~~~~~~]';

  @override
  String get homeServicesHeading => '[Ýöüŕ šéŕṽîçéš~~~~~~]';

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
  String sonarrSizeMb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '[$sizeString Ṁß~~]';
  }

  @override
  String sonarrSizeGb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '[$sizeString Ĝß~~]';
  }

  @override
  String sonarrSizeTb(double size) {
    final intl.NumberFormat sizeNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String sizeString = sizeNumberFormat.format(size);

    return '[$sizeString Ţß~~]';
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
