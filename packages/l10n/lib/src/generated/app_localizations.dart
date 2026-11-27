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
