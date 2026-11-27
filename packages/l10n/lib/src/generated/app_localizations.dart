// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('en', 'XA'),
  ];

  /// Title of the About screen app bar.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// Licensing statement on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Consolarr is free software, licensed under GPL-3.0-or-later.'**
  String get aboutLicense;

  /// Disclaimer on the About screen stating that the project is independent.
  ///
  /// In en, this message translates to:
  /// **'Consolarr is an independent project and is not affiliated with Sonarr, Radarr, the Servarr project or any other app.'**
  String get aboutIndependence;

  /// Title of the home screen app bar.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// Headline of the placeholder state on the home screen before any server is configured.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get homeEmptyHeading;

  /// One-line hint under the placeholder headline on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Add a media server or download client to get started. This screen is a placeholder.'**
  String get homeEmptyBody;

  /// Number of configured servers shown on the home screen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No servers} =1{1 server} other{{count} servers}}'**
  String homeServerCount(int count);

  /// Tooltip and accessible label of the app bar button that opens the About screen.
  ///
  /// In en, this message translates to:
  /// **'About Consolarr'**
  String get homeAboutTooltip;

  /// Plain-language message for a connection problem: wrong or missing credentials.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the credentials.'**
  String get connErrorAuthFailedMessage;

  /// Fix hint shown under the message for a connection problem: wrong or missing credentials.
  ///
  /// In en, this message translates to:
  /// **'Check the API key or the username and password, then test again.'**
  String get connErrorAuthFailedHint;

  /// Plain-language message for a connection problem: stored secrets lost, for example after Keystore loss.
  ///
  /// In en, this message translates to:
  /// **'This server\'s saved credentials are missing.'**
  String get connErrorNeedsCredentialsMessage;

  /// Fix hint shown under the message for a connection problem: stored secrets lost, for example after Keystore loss.
  ///
  /// In en, this message translates to:
  /// **'This can happen after a device restore or a lock screen change. Enter the credentials again.'**
  String get connErrorNeedsCredentialsHint;

  /// Plain-language message for a connection problem: request timed out.
  ///
  /// In en, this message translates to:
  /// **'The server did not answer in time.'**
  String get connErrorTimeoutMessage;

  /// Fix hint shown under the message for a connection problem: request timed out.
  ///
  /// In en, this message translates to:
  /// **'Check that it is running and reachable from this network, or try again.'**
  String get connErrorTimeoutHint;

  /// Plain-language message for a connection problem: pinned certificate changed (blocking).
  ///
  /// In en, this message translates to:
  /// **'The server\'s certificate is different from the one you trusted.'**
  String get connErrorTlsPinMismatchMessage;

  /// Fix hint shown under the message for a connection problem: pinned certificate changed (blocking).
  ///
  /// In en, this message translates to:
  /// **'Connections are blocked. Only trust the new certificate if you know the server\'s certificate was replaced.'**
  String get connErrorTlsPinMismatchHint;

  /// Plain-language message for a connection problem: untrusted or self-signed certificate (trust on first use).
  ///
  /// In en, this message translates to:
  /// **'The server\'s certificate is not trusted by this device.'**
  String get connErrorTlsUntrustedMessage;

  /// Fix hint shown under the message for a connection problem: untrusted or self-signed certificate (trust on first use).
  ///
  /// In en, this message translates to:
  /// **'If this is your own server with a self-signed certificate, review its fingerprint and choose whether to trust it.'**
  String get connErrorTlsUntrustedHint;

  /// Plain-language message for a connection problem: expired or not yet valid certificate.
  ///
  /// In en, this message translates to:
  /// **'The server\'s certificate has expired or is not valid yet.'**
  String get connErrorTlsExpiredMessage;

  /// Fix hint shown under the message for a connection problem: expired or not yet valid certificate.
  ///
  /// In en, this message translates to:
  /// **'Renew the certificate on the server, or check the date on this device.'**
  String get connErrorTlsExpiredHint;

  /// Plain-language message for a connection problem: http refused without the per-server opt-in.
  ///
  /// In en, this message translates to:
  /// **'This address uses plain http, which is not allowed for this server.'**
  String get connErrorCleartextRefusedMessage;

  /// Fix hint shown under the message for a connection problem: http refused without the per-server opt-in.
  ///
  /// In en, this message translates to:
  /// **'Use an https address, or allow plain http for this server in its security settings if it is on a network you trust.'**
  String get connErrorCleartextRefusedHint;

  /// Plain-language message for a connection problem: server version too old or service not supported.
  ///
  /// In en, this message translates to:
  /// **'This server version is not supported.'**
  String get connErrorUnsupportedVersionMessage;

  /// Fix hint shown under the message for a connection problem: server version too old or service not supported.
  ///
  /// In en, this message translates to:
  /// **'Update the server to a current major version.'**
  String get connErrorUnsupportedVersionHint;

  /// Plain-language message for a connection problem: wrong address or path prefix (404).
  ///
  /// In en, this message translates to:
  /// **'Nothing was found at this address.'**
  String get connErrorNotFoundMessage;

  /// Fix hint shown under the message for a connection problem: wrong address or path prefix (404).
  ///
  /// In en, this message translates to:
  /// **'Check the address, port and path prefix. A reverse proxy often needs a prefix such as /sonarr.'**
  String get connErrorNotFoundHint;

  /// Plain-language message for a connection problem: 5xx or unexpected HTTP failure.
  ///
  /// In en, this message translates to:
  /// **'The server reported an error.'**
  String get connErrorServerErrorMessage;

  /// Fix hint shown under the message for a connection problem: 5xx or unexpected HTTP failure.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment. If it keeps happening, check the server\'s own logs.'**
  String get connErrorServerErrorHint;

  /// Plain-language message for a connection problem: connection refused, DNS failure or no network.
  ///
  /// In en, this message translates to:
  /// **'The server could not be reached.'**
  String get connErrorNetworkUnreachableMessage;

  /// Fix hint shown under the message for a connection problem: connection refused, DNS failure or no network.
  ///
  /// In en, this message translates to:
  /// **'Check the address and port, that the server is running, and that this device is on the right network.'**
  String get connErrorNetworkUnreachableHint;

  /// Plain-language message for a connection problem: unexpected response body.
  ///
  /// In en, this message translates to:
  /// **'The server\'s reply could not be understood.'**
  String get connErrorParseErrorMessage;

  /// Fix hint shown under the message for a connection problem: unexpected response body.
  ///
  /// In en, this message translates to:
  /// **'Check that the address points at the right service and not at a login page or proxy.'**
  String get connErrorParseErrorHint;

  /// Plain-language message for a connection problem: redirect refused by the redirect policy.
  ///
  /// In en, this message translates to:
  /// **'The server redirected the request somewhere that is not allowed.'**
  String get connErrorRedirectRefusedMessage;

  /// Fix hint shown under the message for a connection problem: redirect refused by the redirect policy.
  ///
  /// In en, this message translates to:
  /// **'Use the final address of the server directly, and https if it redirects from https to http.'**
  String get connErrorRedirectRefusedHint;

  /// Plain-language message for a connection problem: response over the size limit.
  ///
  /// In en, this message translates to:
  /// **'The server\'s reply was too large.'**
  String get connErrorResponseTooLargeMessage;

  /// Fix hint shown under the message for a connection problem: response over the size limit.
  ///
  /// In en, this message translates to:
  /// **'Check that the address points at the right service.'**
  String get connErrorResponseTooLargeHint;

  /// Plain-language message for a connection problem: form input rejected locally (credentials or query in address, bad path).
  ///
  /// In en, this message translates to:
  /// **'The address or path is not valid.'**
  String get connErrorInvalidInputMessage;

  /// Fix hint shown under the message for a connection problem: form input rejected locally (credentials or query in address, bad path).
  ///
  /// In en, this message translates to:
  /// **'Enter an address like https://host:port without a username, password or key, and a path that starts with a slash.'**
  String get connErrorInvalidInputHint;

  /// The app name, shown in the task switcher and as the accessible name of the app.
  ///
  /// In en, this message translates to:
  /// **'Consolarr'**
  String get appTitle;

  /// Title of the Sonarr series library screen and its floating top bar.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get sonarrTitle;

  /// Tooltip and accessible name of the top bar button that switches the series library from the poster grid to the list.
  ///
  /// In en, this message translates to:
  /// **'Show as list'**
  String get sonarrSwitchToListTooltip;

  /// Tooltip and accessible name of the top bar button that switches the series library from the list to the poster grid.
  ///
  /// In en, this message translates to:
  /// **'Show as grid'**
  String get sonarrSwitchToGridTooltip;

  /// Accessible label of the skeleton shown while the series library loads.
  ///
  /// In en, this message translates to:
  /// **'Loading series'**
  String get sonarrLoadingLabel;

  /// Label of the retry button on error and offline states of the series library.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sonarrRetry;

  /// Headline of the empty series library state when Sonarr has no series.
  ///
  /// In en, this message translates to:
  /// **'No series yet'**
  String get sonarrEmptyHeadline;

  /// Hint under the empty series library headline.
  ///
  /// In en, this message translates to:
  /// **'Series you add in Sonarr will show up here.'**
  String get sonarrEmptyMessage;

  /// Primary action of the empty series library state; reloads the list.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get sonarrEmptyAction;

  /// Headline shown in the series library when no Sonarr server has been added.
  ///
  /// In en, this message translates to:
  /// **'No Sonarr server'**
  String get sonarrNoServerHeadline;

  /// Hint under the no-server headline of the series library.
  ///
  /// In en, this message translates to:
  /// **'Add your Sonarr server to browse your series.'**
  String get sonarrNoServerMessage;

  /// Primary action of the no-server state; opens the servers screen.
  ///
  /// In en, this message translates to:
  /// **'Add a server'**
  String get sonarrNoServerAction;

  /// Secondary action on series library errors that are fixed in the server settings (credentials, certificate).
  ///
  /// In en, this message translates to:
  /// **'Check server settings'**
  String get sonarrOpenServers;

  /// Headline of the series library error state for connection and server problems.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your series'**
  String get sonarrErrorTitle;

  /// Headline of the series library error state when the credentials are wrong or missing.
  ///
  /// In en, this message translates to:
  /// **'Sonarr rejected the sign-in'**
  String get sonarrErrorAuthTitle;

  /// Headline of the series library error state when the Sonarr version is too old.
  ///
  /// In en, this message translates to:
  /// **'Unsupported Sonarr version'**
  String get sonarrErrorVersionTitle;

  /// Plain-language cause shown in the series library error state (Auth).
  ///
  /// In en, this message translates to:
  /// **'The API key or password was not accepted.'**
  String get sonarrErrorAuthMessage;

  /// Likely fix shown under the cause in the series library error state (Auth).
  ///
  /// In en, this message translates to:
  /// **'Check the credentials in the server settings.'**
  String get sonarrErrorAuthHint;

  /// Plain-language cause shown in the series library error state (NeedsCredentials).
  ///
  /// In en, this message translates to:
  /// **'The saved credentials for this server are missing.'**
  String get sonarrErrorNeedsCredentialsMessage;

  /// Likely fix shown under the cause in the series library error state (NeedsCredentials).
  ///
  /// In en, this message translates to:
  /// **'Enter the API key or password again in the server settings.'**
  String get sonarrErrorNeedsCredentialsHint;

  /// Plain-language cause shown in the series library error state (Network).
  ///
  /// In en, this message translates to:
  /// **'Sonarr could not be reached.'**
  String get sonarrErrorNetworkMessage;

  /// Likely fix shown under the cause in the series library error state (Network).
  ///
  /// In en, this message translates to:
  /// **'Check that you are on the right network and that the address and port are correct.'**
  String get sonarrErrorNetworkHint;

  /// Plain-language cause shown in the series library error state (Timeout).
  ///
  /// In en, this message translates to:
  /// **'Sonarr took too long to answer.'**
  String get sonarrErrorTimeoutMessage;

  /// Likely fix shown under the cause in the series library error state (Timeout).
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment, or check that the server is running and not overloaded.'**
  String get sonarrErrorTimeoutHint;

  /// Plain-language cause shown in the series library error state (Version).
  ///
  /// In en, this message translates to:
  /// **'This Sonarr version is too old for Consolarr.'**
  String get sonarrErrorVersionMessage;

  /// Likely fix shown under the cause in the series library error state (Version).
  ///
  /// In en, this message translates to:
  /// **'Update Sonarr to version 3 or newer.'**
  String get sonarrErrorVersionHint;

  /// Plain-language cause shown in the series library error state (Server).
  ///
  /// In en, this message translates to:
  /// **'Sonarr reported an internal problem.'**
  String get sonarrErrorServerMessage;

  /// Likely fix shown under the cause in the series library error state (Server).
  ///
  /// In en, this message translates to:
  /// **'Check the Sonarr logs, then try again.'**
  String get sonarrErrorServerHint;

  /// Plain-language cause shown in the series library error state (Parse).
  ///
  /// In en, this message translates to:
  /// **'Sonarr sent an answer the app could not read.'**
  String get sonarrErrorParseMessage;

  /// Likely fix shown under the cause in the series library error state (Parse).
  ///
  /// In en, this message translates to:
  /// **'Make sure the address points to Sonarr and not to another service.'**
  String get sonarrErrorParseHint;

  /// Plain-language cause shown in the series library error state (NotFound).
  ///
  /// In en, this message translates to:
  /// **'Nothing answered at this address.'**
  String get sonarrErrorNotFoundMessage;

  /// Likely fix shown under the cause in the series library error state (NotFound).
  ///
  /// In en, this message translates to:
  /// **'Check the address and the path prefix, for example /sonarr behind a reverse proxy.'**
  String get sonarrErrorNotFoundHint;

  /// Plain-language cause shown in the series library error state (Tls).
  ///
  /// In en, this message translates to:
  /// **'The server\'s certificate is not trusted.'**
  String get sonarrErrorTlsMessage;

  /// Likely fix shown under the cause in the series library error state (Tls).
  ///
  /// In en, this message translates to:
  /// **'Review the certificate in the server settings before trusting it.'**
  String get sonarrErrorTlsHint;

  /// Plain-language cause shown in the series library error state (Cleartext).
  ///
  /// In en, this message translates to:
  /// **'This server uses plain http, which is not allowed.'**
  String get sonarrErrorCleartextMessage;

  /// Likely fix shown under the cause in the series library error state (Cleartext).
  ///
  /// In en, this message translates to:
  /// **'Use https, or allow plain http for this server in its settings.'**
  String get sonarrErrorCleartextHint;

  /// Plain-language cause shown in the series library error state (Generic).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while talking to Sonarr.'**
  String get sonarrErrorGenericMessage;

  /// Likely fix shown under the cause in the series library error state (Generic).
  ///
  /// In en, this message translates to:
  /// **'Try again, and check the server settings if it keeps happening.'**
  String get sonarrErrorGenericHint;

  /// Message of the banner above cached series when Sonarr cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Offline. Showing your saved series.'**
  String get sonarrOfflineMessage;

  /// Age line of the offline banner, for example "Updated 5 minutes ago".
  ///
  /// In en, this message translates to:
  /// **'Updated {age}'**
  String sonarrUpdatedAgo(String age);

  /// Relative age used when cached data is less than a minute old.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get sonarrAgeJustNow;

  /// Relative age in minutes for the offline banner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String sonarrAgeMinutes(int count);

  /// Relative age in hours for the offline banner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String sonarrAgeHours(int count);

  /// Relative age in days for the offline banner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String sonarrAgeDays(int count);

  /// Badge text for a series that is still airing.
  ///
  /// In en, this message translates to:
  /// **'Continuing'**
  String get sonarrStatusContinuing;

  /// Badge text for a series that has ended.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get sonarrStatusEnded;

  /// Badge text for a series that has not started airing.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get sonarrStatusUpcoming;

  /// Badge text for a series that was removed from the metadata source.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get sonarrStatusDeleted;

  /// Text saying Sonarr monitors the series for new episodes.
  ///
  /// In en, this message translates to:
  /// **'Monitored'**
  String get sonarrMonitored;

  /// Badge and text saying Sonarr does not monitor the series.
  ///
  /// In en, this message translates to:
  /// **'Unmonitored'**
  String get sonarrUnmonitored;

  /// Compact episode progress on a poster card: downloaded over total.
  ///
  /// In en, this message translates to:
  /// **'{have}/{total}'**
  String sonarrEpisodesShort(int have, int total);

  /// Episode progress in the series list: downloaded over total episodes.
  ///
  /// In en, this message translates to:
  /// **'{total, plural, =1{{have}/1 episode} other{{have}/{total} episodes}}'**
  String sonarrEpisodesProgress(int have, int total);

  /// Number of seasons of a series.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 season} other{{count} seasons}}'**
  String sonarrSeasonCount(int count);

  /// Size on disk in megabytes.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String sonarrSizeMb(String size);

  /// Size on disk in gigabytes.
  ///
  /// In en, this message translates to:
  /// **'{size} GB'**
  String sonarrSizeGb(String size);

  /// Size on disk in terabytes.
  ///
  /// In en, this message translates to:
  /// **'{size} TB'**
  String sonarrSizeTb(String size);

  /// Relative label for a series whose next episode airs today.
  ///
  /// In en, this message translates to:
  /// **'Airs today'**
  String get sonarrNextAiringToday;

  /// Relative label for a series whose next episode airs tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Airs tomorrow'**
  String get sonarrNextAiringTomorrow;

  /// Relative label for the next episode airing in a number of days.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Airs in 1 day} other{Airs in {days} days}}'**
  String sonarrNextAiringInDays(int days);

  /// Screen reader label of a series card: the title followed by its status details.
  ///
  /// In en, this message translates to:
  /// **'{title}, {details}'**
  String sonarrSeriesSemantics(String title, String details);

  /// Title of the torrent list screen top bar.
  ///
  /// In en, this message translates to:
  /// **'Torrents'**
  String get torrentsTitle;

  /// Number of torrents shown in the speed header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No torrents} =1{1 torrent} other{{count} torrents}}'**
  String torCount(int count);

  /// Label of the global download speed in the speed header.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get torSpeedDown;

  /// Label of the global upload speed in the speed header.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get torSpeedUp;

  /// Shown instead of a speed when nothing is transferring.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get torSpeedIdle;

  /// Shown in the speed header when only the transfer statistics failed to load while the torrent list loaded.
  ///
  /// In en, this message translates to:
  /// **'Speed information is unavailable right now.'**
  String get torSpeedPartial;

  /// Shown in the speed header while the server is unreachable.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get torSpeedOffline;

  /// Spoken summary of the speed header for screen readers.
  ///
  /// In en, this message translates to:
  /// **'Download {down}, upload {up}, {count, plural, =0{no torrents} =1{1 torrent} other{{count} torrents}}'**
  String torSpeedHeaderSemantics(String down, String up, int count);

  /// Torrent state: actively downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get torStateDownloading;

  /// Torrent state: no peers are sending data.
  ///
  /// In en, this message translates to:
  /// **'Stalled'**
  String get torStateStalled;

  /// Torrent state: verifying files on disk.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get torStateChecking;

  /// Torrent state: waiting for a free slot.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get torStateQueued;

  /// Torrent state: complete and uploading to peers.
  ///
  /// In en, this message translates to:
  /// **'Seeding'**
  String get torStateSeeding;

  /// Torrent state: paused by the user.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get torStatePaused;

  /// Torrent state: complete and idle.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get torStateFinished;

  /// Torrent state: the client reports an error for this torrent.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get torStateError;

  /// Torrent state: the client reported a state the app does not know.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get torStateUnknown;

  /// Percentage of a torrent that is complete, for example 45%.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String torProgressPercent(double value);

  /// Spoken description of a torrent row: name, state and percentage in words.
  ///
  /// In en, this message translates to:
  /// **'{name}, {state}, {percent} complete'**
  String torRowSemantics(String name, String state, String percent);

  /// Total size of a torrent in the row metadata.
  ///
  /// In en, this message translates to:
  /// **'{size}'**
  String torDetailSize(String size);

  /// Download speed of one torrent in the row metadata.
  ///
  /// In en, this message translates to:
  /// **'Down {speed}'**
  String torDetailDown(String speed);

  /// Upload speed of one torrent in the row metadata.
  ///
  /// In en, this message translates to:
  /// **'Up {speed}'**
  String torDetailUp(String speed);

  /// Estimated time remaining in the row metadata.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String torDetailEta(String time);

  /// Share ratio in the row metadata.
  ///
  /// In en, this message translates to:
  /// **'Ratio {ratio}'**
  String torDetailRatio(double ratio);

  /// A speed: a formatted size per second.
  ///
  /// In en, this message translates to:
  /// **'{size}/s'**
  String torSpeedPerSecond(String size);

  /// Size in bytes.
  ///
  /// In en, this message translates to:
  /// **'{value} B'**
  String torUnitB(double value);

  /// Size in kilobytes.
  ///
  /// In en, this message translates to:
  /// **'{value} KB'**
  String torUnitKB(double value);

  /// Size in megabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String torUnitMB(double value);

  /// Size in gigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String torUnitGB(double value);

  /// Size in terabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} TB'**
  String torUnitTB(double value);

  /// A duration in seconds, short form.
  ///
  /// In en, this message translates to:
  /// **'{count}s'**
  String torDurationSeconds(int count);

  /// A duration in minutes, short form.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String torDurationMinutes(int count);

  /// A duration in hours and minutes, short form.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String torDurationHoursMinutes(int hours, int minutes);

  /// A duration in days and hours, short form.
  ///
  /// In en, this message translates to:
  /// **'{days}d {hours}h'**
  String torDurationDaysHours(int days, int hours);

  /// Headline when the client has no torrents.
  ///
  /// In en, this message translates to:
  /// **'No torrents yet'**
  String get torEmptyHeadline;

  /// Hint under the empty headline.
  ///
  /// In en, this message translates to:
  /// **'Torrents you add in your client will show up here.'**
  String get torEmptyMessage;

  /// Headline when no torrent client server is configured.
  ///
  /// In en, this message translates to:
  /// **'No torrent client yet'**
  String get torNoServerHeadline;

  /// Hint when no torrent client server is configured.
  ///
  /// In en, this message translates to:
  /// **'Add a qBittorrent server to see your torrents.'**
  String get torNoServerMessage;

  /// Button that opens the server setup.
  ///
  /// In en, this message translates to:
  /// **'Add a server'**
  String get torNoServerAction;

  /// Headline of the error state of the torrent list.
  ///
  /// In en, this message translates to:
  /// **'Can\'t load torrents'**
  String get torErrorHeadline;

  /// Button that retries loading the torrent list.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get torRetry;

  /// Banner text while offline with cached torrents.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Showing the last data.'**
  String get torOfflineMessage;

  /// Age of the data shown under the offline banner.
  ///
  /// In en, this message translates to:
  /// **'Updated {time} ago'**
  String torOfflineAge(String time);

  /// Age text when the data is less than a few seconds old.
  ///
  /// In en, this message translates to:
  /// **'Updated just now'**
  String get torOfflineJustNow;

  /// Button on the offline banner that tries to reach the server again.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get torReconnect;

  /// Accessible hint of the speed header when it can be tapped.
  ///
  /// In en, this message translates to:
  /// **'Open speed limits'**
  String get torSpeedLimitsHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'XA':
            return AppLocalizationsEnXa();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
