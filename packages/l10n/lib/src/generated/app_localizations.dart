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
  /// **'Add a media server or download client to get started.'**
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

  /// Title of the servers list screen.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get serversTitle;

  /// Tooltip and accessible label of the add-server button in the servers list top bar.
  ///
  /// In en, this message translates to:
  /// **'Add a server'**
  String get serversAddTooltip;

  /// Headline of the servers list when no server is configured.
  ///
  /// In en, this message translates to:
  /// **'No servers yet'**
  String get serversEmptyHeadline;

  /// Hint under the empty servers list headline.
  ///
  /// In en, this message translates to:
  /// **'Add Sonarr or qBittorrent to browse your library and downloads from here.'**
  String get serversEmptyMessage;

  /// Primary action label of the empty servers list.
  ///
  /// In en, this message translates to:
  /// **'Add your first server'**
  String get serversEmptyAction;

  /// Headline when the saved servers could not be read from the device.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your servers'**
  String get serversLoadErrorHeadline;

  /// Message when the saved servers could not be read.
  ///
  /// In en, this message translates to:
  /// **'The saved servers could not be read from this device.'**
  String get serversLoadErrorMessage;

  /// Retry button label in the servers feature.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get serversRetry;

  /// Cancel button label in servers dialogs.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get serversCancel;

  /// Display name of the Sonarr service (brand name).
  ///
  /// In en, this message translates to:
  /// **'Sonarr'**
  String get serverKindSonarr;

  /// Display name of the Radarr service (brand name).
  ///
  /// In en, this message translates to:
  /// **'Radarr'**
  String get serverKindRadarr;

  /// Display name of the qBittorrent service (brand name).
  ///
  /// In en, this message translates to:
  /// **'qBittorrent'**
  String get serverKindQbittorrent;

  /// Display name of the Transmission service (brand name).
  ///
  /// In en, this message translates to:
  /// **'Transmission'**
  String get serverKindTransmission;

  /// Display name of the Deluge service (brand name).
  ///
  /// In en, this message translates to:
  /// **'Deluge'**
  String get serverKindDeluge;

  /// Short description of Sonarr on the service choice tile.
  ///
  /// In en, this message translates to:
  /// **'TV series library'**
  String get serverKindSonarrDescription;

  /// Short description of qBittorrent on the service choice tile.
  ///
  /// In en, this message translates to:
  /// **'Torrent downloads'**
  String get serverKindQbittorrentDescription;

  /// Description for a service that is not supported yet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet'**
  String get serverKindOtherDescription;

  /// Health text of a server being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get serverHealthChecking;

  /// Health text of a healthy server.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get serverHealthHealthy;

  /// Health text of a server that answers with errors or slowly.
  ///
  /// In en, this message translates to:
  /// **'Responding with problems'**
  String get serverHealthDegraded;

  /// Health text of a server that rejected the credentials.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get serverHealthUnauthorized;

  /// Health text of a server that cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get serverHealthUnreachable;

  /// Health text when the health check itself failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check'**
  String get serverHealthUnknown;

  /// Warning badge on a server that is allowed to use unencrypted http.
  ///
  /// In en, this message translates to:
  /// **'Plain http'**
  String get serverBadgeCleartext;

  /// Badge on a server whose saved secrets are missing.
  ///
  /// In en, this message translates to:
  /// **'Needs credentials'**
  String get serverBadgeNeedsCredentials;

  /// Badge on the server used by default for its service.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get serverBadgeActive;

  /// Badge on the server opened when the app starts.
  ///
  /// In en, this message translates to:
  /// **'Opens at launch'**
  String get serverBadgeStartup;

  /// Tooltip and accessible label of the per-server actions menu.
  ///
  /// In en, this message translates to:
  /// **'More actions for {name}'**
  String serverMenuTooltip(String name);

  /// Accessible label of the drag handle that reorders a server.
  ///
  /// In en, this message translates to:
  /// **'Reorder {name}'**
  String serverDragHandleLabel(String name);

  /// Menu action: edit a server.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get serverActionEdit;

  /// Menu action: use this server by default for its service.
  ///
  /// In en, this message translates to:
  /// **'Make active'**
  String get serverActionSetActive;

  /// Menu action: open this server when the app starts.
  ///
  /// In en, this message translates to:
  /// **'Open at launch'**
  String get serverActionSetStartup;

  /// Menu action: stop opening this server at launch.
  ///
  /// In en, this message translates to:
  /// **'Don\'t open at launch'**
  String get serverActionClearStartup;

  /// Menu action: move a server up in the list (alternative to dragging).
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get serverActionMoveUp;

  /// Menu action: move a server down in the list (alternative to dragging).
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get serverActionMoveDown;

  /// Menu action: delete a server.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get serverActionDelete;

  /// Title of the delete-server confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String serverDeleteTitle(String name);

  /// Consequences spelled out in the delete-server confirmation.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved credentials, the trusted certificate and the cached data for this server from this device. The server itself is not changed.'**
  String get serverDeleteBody;

  /// Confirm button of the delete-server dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get serverDeleteConfirm;

  /// Title of the server editor when creating a server.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get serverEditorTitleNew;

  /// Title of the server editor when editing a server.
  ///
  /// In en, this message translates to:
  /// **'Edit server'**
  String get serverEditorTitleEdit;

  /// Save button of the server editor.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get serverEditorSave;

  /// Headline shown when saving a server failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the server'**
  String get serverSaveFailedHeadline;

  /// Section heading: service type and name.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serverSectionService;

  /// Section heading: server address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get serverSectionAddress;

  /// Section heading: authentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get serverSectionAuth;

  /// Section heading: custom request headers.
  ///
  /// In en, this message translates to:
  /// **'Custom headers'**
  String get serverSectionHeaders;

  /// Section heading: transport security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get serverSectionSecurity;

  /// Label of the server display name field.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get serverFieldName;

  /// Label of the server address field.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get serverFieldAddress;

  /// Placeholder example for the server address field.
  ///
  /// In en, this message translates to:
  /// **'https://host.example:8989'**
  String get serverFieldAddressHint;

  /// Label of the optional reverse-proxy path prefix field.
  ///
  /// In en, this message translates to:
  /// **'Path prefix (optional)'**
  String get serverFieldPathPrefix;

  /// Helper text under the path prefix field.
  ///
  /// In en, this message translates to:
  /// **'Only needed if a reverse proxy serves the app under a path, for example /sonarr.'**
  String get serverPathPrefixHelper;

  /// Authentication mode: no credentials.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get serverAuthNone;

  /// Authentication mode: API key.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get serverAuthApiKey;

  /// Authentication mode: username and password.
  ///
  /// In en, this message translates to:
  /// **'Username and password'**
  String get serverAuthBasic;

  /// Label of the API key field.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get serverFieldApiKey;

  /// Label of the username field.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get serverFieldUsername;

  /// Label of the password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get serverFieldPassword;

  /// Helper under a secret field when editing a server with a saved secret.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the saved value.'**
  String get serverSecretKeepHint;

  /// Tooltip of the button that reveals a secret field.
  ///
  /// In en, this message translates to:
  /// **'Show value'**
  String get serverSecretShow;

  /// Tooltip of the button that hides a secret field.
  ///
  /// In en, this message translates to:
  /// **'Hide value'**
  String get serverSecretHide;

  /// Helper text of the custom headers section.
  ///
  /// In en, this message translates to:
  /// **'For reverse-proxy gateways. Values are stored securely on this device.'**
  String get serverHeadersHelper;

  /// Label of a custom header name field.
  ///
  /// In en, this message translates to:
  /// **'Header name'**
  String get serverHeaderName;

  /// Label of a custom header value field.
  ///
  /// In en, this message translates to:
  /// **'Header value'**
  String get serverHeaderValue;

  /// Button that adds a custom header row.
  ///
  /// In en, this message translates to:
  /// **'Add header'**
  String get serverHeaderAdd;

  /// Tooltip of the button that removes a custom header row.
  ///
  /// In en, this message translates to:
  /// **'Remove header'**
  String get serverHeaderRemove;

  /// Label of the per-server switch that allows unencrypted http.
  ///
  /// In en, this message translates to:
  /// **'Allow plain http'**
  String get serverCleartextTitle;

  /// Risk explanation shown with the plain http switch.
  ///
  /// In en, this message translates to:
  /// **'Plain http sends your API key, password and every response without encryption, so anyone on the network can read them. Only allow it on a network you trust, such as your home network.'**
  String get serverCleartextRisk;

  /// Hint shown when the address is http but plain http is not allowed.
  ///
  /// In en, this message translates to:
  /// **'This address uses http. Turn on plain http, or use an https address.'**
  String get serverCleartextNeeded;

  /// Validation error: empty display name.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for this server.'**
  String get serverErrorNameRequired;

  /// Validation error: empty address.
  ///
  /// In en, this message translates to:
  /// **'Enter the server address.'**
  String get serverErrorAddressRequired;

  /// Validation error: address is not a valid http(s) URL.
  ///
  /// In en, this message translates to:
  /// **'Enter a full address such as https://host.example:8989.'**
  String get serverErrorAddressInvalid;

  /// Validation error: address contains credentials.
  ///
  /// In en, this message translates to:
  /// **'Don\'t put a username or password in the address. Use the fields below.'**
  String get serverErrorAddressCredentials;

  /// Validation error: address contains a query string.
  ///
  /// In en, this message translates to:
  /// **'Remove everything after the ? in the address. Keys belong in the key field.'**
  String get serverErrorAddressQuery;

  /// Validation error: the port in the address is not between 1 and 65535.
  ///
  /// In en, this message translates to:
  /// **'The port must be a number from 1 to 65535.'**
  String get serverErrorAddressPort;

  /// Validation error: the host name contains non-ASCII characters; the user should enter its ASCII (punycode) form.
  ///
  /// In en, this message translates to:
  /// **'Use the ASCII form of the host name (for example xn--...), not special characters.'**
  String get serverErrorAddressNonAscii;

  /// Validation error: the address origin changed, so the stored key or password must be entered again before saving or testing.
  ///
  /// In en, this message translates to:
  /// **'You changed the server address. Enter the key or password again; stored secrets are never sent to a different address.'**
  String get serverErrorSecretsReenter;

  /// Hint shown above the credential fields after the address (scheme, host or port) was changed: stored secrets are not reused.
  ///
  /// In en, this message translates to:
  /// **'You changed the server address, so the stored key or password will not be used. Enter it again.'**
  String get serverSecretReenterHint;

  /// Validation error: invalid path prefix.
  ///
  /// In en, this message translates to:
  /// **'Use a path such as /sonarr, without spaces, ? or ...'**
  String get serverErrorPrefixInvalid;

  /// Validation error: invalid or duplicate header names.
  ///
  /// In en, this message translates to:
  /// **'Header names may use letters, digits and - _ . only, and must be unique.'**
  String get serverErrorHeaderInvalid;

  /// Button that tests the connection to the server.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get serverTestButton;

  /// Shown while the connection test runs.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get serverTestTesting;

  /// Connection test success message.
  ///
  /// In en, this message translates to:
  /// **'Connected. Server version {version}.'**
  String serverTestSuccess(String version);

  /// Short success chip label for the connection test.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get serverTestSuccessLabel;

  /// Short failure chip label for the connection test.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get serverTestFailedLabel;

  /// Heading of the pinned certificate details.
  ///
  /// In en, this message translates to:
  /// **'Trusted certificate'**
  String get serverPinTitle;

  /// Label of the pinned certificate fingerprint.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 fingerprint'**
  String get serverPinFingerprint;

  /// Button that forgets the pinned certificate.
  ///
  /// In en, this message translates to:
  /// **'Remove trusted certificate'**
  String get serverPinRemove;

  /// Title of the confirmation for forgetting a pin.
  ///
  /// In en, this message translates to:
  /// **'Remove trusted certificate?'**
  String get serverPinRemoveTitle;

  /// Consequence text of the forget-pin confirmation.
  ///
  /// In en, this message translates to:
  /// **'The next connection will ask you to review the server\'s certificate again.'**
  String get serverPinRemoveBody;

  /// Confirm button of the forget-pin dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get serverPinRemoveConfirm;

  /// Banner in the editor when the saved secrets are missing.
  ///
  /// In en, this message translates to:
  /// **'The saved credentials for this server are missing. Enter them again and save.'**
  String get serverNeedsCredentialsBanner;

  /// Title of the unsaved-changes dialog.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get serverDiscardTitle;

  /// Body of the unsaved-changes dialog.
  ///
  /// In en, this message translates to:
  /// **'Your changes to this server haven\'t been saved.'**
  String get serverDiscardBody;

  /// Discard button of the unsaved-changes dialog.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get serverDiscardConfirm;

  /// Keep-editing button of the unsaved-changes dialog.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get serverDiscardKeep;

  /// Title of the certificate sheet on first contact.
  ///
  /// In en, this message translates to:
  /// **'Trust this certificate?'**
  String get certSheetTitleFirstUse;

  /// Explanation on the first-use certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'This server uses a certificate your device doesn\'t recognise. Compare the fingerprint with the one on your server before trusting it.'**
  String get certSheetExplanationFirstUse;

  /// Title of the certificate sheet when a pinned certificate changed.
  ///
  /// In en, this message translates to:
  /// **'Certificate changed'**
  String get certSheetTitleMismatch;

  /// Explanation on the mismatch certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'This server now presents a different certificate than the one you trusted. Connections stay blocked until you decide.'**
  String get certSheetExplanationMismatch;

  /// Prominent warning on the mismatch certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'If you did not replace the certificate yourself, someone may be intercepting the connection. Do not trust it.'**
  String get certSheetMismatchWarning;

  /// Title of the certificate sheet for an expired certificate.
  ///
  /// In en, this message translates to:
  /// **'Certificate expired'**
  String get certSheetTitleExpired;

  /// Explanation on the expired certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'This server\'s certificate is expired or not valid yet, so it cannot be trusted. Renew it on the server.'**
  String get certSheetExplanationExpired;

  /// Label of the certificate fingerprint on the sheet.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 fingerprint'**
  String get certSheetFingerprint;

  /// Label of the previously pinned fingerprint on the mismatch sheet.
  ///
  /// In en, this message translates to:
  /// **'Previously trusted fingerprint'**
  String get certSheetPreviousFingerprint;

  /// Label of the certificate subject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get certSheetSubject;

  /// Label of the certificate issuer.
  ///
  /// In en, this message translates to:
  /// **'Issuer'**
  String get certSheetIssuer;

  /// Label of the certificate validity period.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get certSheetValidity;

  /// Certificate validity range text.
  ///
  /// In en, this message translates to:
  /// **'{from} to {until}'**
  String certSheetValidityRange(String from, String until);

  /// Accept button of the first-use certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'Trust certificate'**
  String get certSheetAccept;

  /// Accept (re-trust) button of the mismatch certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'Trust new certificate'**
  String get certSheetAcceptMismatch;

  /// Reject button of the certificate sheet.
  ///
  /// In en, this message translates to:
  /// **'Don\'t trust'**
  String get certSheetReject;

  /// Accessible label of the sheet drag handle.
  ///
  /// In en, this message translates to:
  /// **'Drag handle'**
  String get certSheetHandle;

  /// Headline of the first-run welcome step.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Consolarr'**
  String get onboardingWelcomeTitle;

  /// Body text of the first-run welcome step.
  ///
  /// In en, this message translates to:
  /// **'Control your self-hosted media services from your phone. Let\'s connect your first server.'**
  String get onboardingWelcomeBody;

  /// Primary button of the welcome step.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingStart;

  /// Button that skips first-run setup.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get onboardingSkip;

  /// Headline of the service choice step.
  ///
  /// In en, this message translates to:
  /// **'Which service?'**
  String get onboardingChooseTitle;

  /// Body text of the service choice step.
  ///
  /// In en, this message translates to:
  /// **'You can add more servers later.'**
  String get onboardingChooseBody;

  /// Headline of the details step.
  ///
  /// In en, this message translates to:
  /// **'Server details'**
  String get onboardingDetailsTitle;

  /// Headline of the test step.
  ///
  /// In en, this message translates to:
  /// **'Test and finish'**
  String get onboardingTestTitle;

  /// Next button of the onboarding stepper.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Back button of the onboarding stepper.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// Finish button of the onboarding stepper.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// Progress text of the onboarding stepper.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepOf(int current, int total);

  /// Hint on the test step until the connection test succeeded.
  ///
  /// In en, this message translates to:
  /// **'Test the connection before finishing.'**
  String get onboardingTestFirst;

  /// The app name, shown in the task switcher and as the accessible name of the app.
  ///
  /// In en, this message translates to:
  /// **'Consolarr'**
  String get appTitle;

  /// Label of the Home destination in the bottom navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Label of the Sonarr (TV series) destination in the bottom navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get navSonarr;

  /// Label of the torrent client destination in the bottom navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Torrents'**
  String get navTorrents;

  /// Label of the Servers destination in the bottom navigation bar.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get navServers;

  /// Accessibility hint announced for the currently selected navigation destination.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get navSelectedHint;

  /// Title of the sheet that lets the user pick the active server for a service.
  ///
  /// In en, this message translates to:
  /// **'Switch server'**
  String get switcherTitle;

  /// Tooltip and accessible label of the top bar button that opens the server switcher.
  ///
  /// In en, this message translates to:
  /// **'Switch server'**
  String get switcherTooltip;

  /// Text marking the currently active server in the server switcher.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get switcherActive;

  /// Message in the server switcher when no server of the service type exists.
  ///
  /// In en, this message translates to:
  /// **'No servers of this type yet.'**
  String get switcherEmpty;

  /// Short health status text: the server answered correctly.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get healthHealthy;

  /// Short health status text: a health check is running.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get healthChecking;

  /// Short health status text: the server answers but with errors or very slowly.
  ///
  /// In en, this message translates to:
  /// **'Slow or erroring'**
  String get healthDegraded;

  /// Short health status text: the server rejected the credentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong credentials'**
  String get healthUnauthorized;

  /// Short health status text: the server cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get healthUnreachable;

  /// Primary button on the Home screen that starts first-run server setup.
  ///
  /// In en, this message translates to:
  /// **'Set up a server'**
  String get homeSetupCta;

  /// Heading above the list of configured services on the Home screen.
  ///
  /// In en, this message translates to:
  /// **'Your services'**
  String get homeServicesHeading;

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
