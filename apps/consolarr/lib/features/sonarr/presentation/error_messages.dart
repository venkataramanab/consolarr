// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:l10n/l10n.dart';

/// Copy for one failure: headline, plain-language cause and a fix hint.
class SonarrErrorCopy {
  const SonarrErrorCopy({
    required this.title,
    required this.message,
    required this.hint,
    this.fixedInServerSettings = false,
  });

  final String title;
  final String message;
  final String hint;

  /// The fix lives in the server settings (offer a shortcut).
  final bool fixedInServerSettings;
}

/// `debugDetail` of the `auth_failed` raised when stored secrets are missing.
const _needsCredentials = 'needs_credentials';

/// Maps any [AppError] to copy for the series library.
SonarrErrorCopy sonarrErrorCopy(AppLocalizations l10n, AppError error) {
  SonarrErrorCopy generic(String message, String hint, {bool fix = false}) =>
      SonarrErrorCopy(
        title: l10n.sonarrErrorTitle,
        message: message,
        hint: hint,
        fixedInServerSettings: fix,
      );
  return switch (error.category) {
    ErrorCategory.authFailed when error.debugDetail == _needsCredentials =>
      SonarrErrorCopy(
        title: l10n.sonarrErrorAuthTitle,
        message: l10n.sonarrErrorNeedsCredentialsMessage,
        hint: l10n.sonarrErrorNeedsCredentialsHint,
        fixedInServerSettings: true,
      ),
    ErrorCategory.authFailed => SonarrErrorCopy(
      title: l10n.sonarrErrorAuthTitle,
      message: l10n.sonarrErrorAuthMessage,
      hint: l10n.sonarrErrorAuthHint,
      fixedInServerSettings: true,
    ),
    ErrorCategory.unsupportedVersion => SonarrErrorCopy(
      title: l10n.sonarrErrorVersionTitle,
      message: l10n.sonarrErrorVersionMessage,
      hint: l10n.sonarrErrorVersionHint,
    ),
    ErrorCategory.networkUnreachable => generic(
      l10n.sonarrErrorNetworkMessage,
      l10n.sonarrErrorNetworkHint,
    ),
    ErrorCategory.timeout => generic(
      l10n.sonarrErrorTimeoutMessage,
      l10n.sonarrErrorTimeoutHint,
    ),
    ErrorCategory.serverError => generic(
      l10n.sonarrErrorServerMessage,
      l10n.sonarrErrorServerHint,
    ),
    ErrorCategory.parseError => generic(
      l10n.sonarrErrorParseMessage,
      l10n.sonarrErrorParseHint,
    ),
    ErrorCategory.notFound => generic(
      l10n.sonarrErrorNotFoundMessage,
      l10n.sonarrErrorNotFoundHint,
      fix: true,
    ),
    ErrorCategory.tlsUntrusted ||
    ErrorCategory.tlsExpired ||
    ErrorCategory.tlsPinMismatch => generic(
      l10n.sonarrErrorTlsMessage,
      l10n.sonarrErrorTlsHint,
      fix: true,
    ),
    ErrorCategory.cleartextRefused => generic(
      l10n.sonarrErrorCleartextMessage,
      l10n.sonarrErrorCleartextHint,
      fix: true,
    ),
    ErrorCategory.requestTooLarge => generic(
      l10n.sonarrErrorRequestTooLargeMessage,
      l10n.sonarrErrorRequestTooLargeHint,
    ),
    ErrorCategory.redirectRefused || ErrorCategory.responseTooLarge => generic(
      l10n.sonarrErrorGenericMessage,
      l10n.sonarrErrorGenericHint,
    ),
  };
}

/// Copy for an unexpected non-[AppError] failure.
SonarrErrorCopy sonarrUnexpectedErrorCopy(AppLocalizations l10n) =>
    SonarrErrorCopy(
      title: l10n.sonarrErrorTitle,
      message: l10n.sonarrErrorGenericMessage,
      hint: l10n.sonarrErrorGenericHint,
    );
