// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:l10n/l10n.dart';

/// A localized, plain-language failure message with a fix hint.
class ErrorMessage {
  const ErrorMessage({required this.message, required this.hint});

  final String message;
  final String hint;
}

/// `debugDetail` values `ServerProfile.parse` uses for local input problems.
const _invalidInputDetails = {
  'invalid address',
  'address must not contain credentials',
  'address must not contain a query string',
  'invalid path prefix',
  'invalid headers',
};

/// `debugDetail` of the `auth_failed` raised when stored secrets are missing.
const needsCredentialsDetail = 'needs_credentials';

/// Maps any [AppError] to copy (SRV-05). One pair of ARB keys per category:
/// `connError<Category>Message` and `connError<Category>Hint`.
///
/// The typed TLS errors from the security package carry their own category
/// (`tls_untrusted`, `tls_expired`, `tls_pin_mismatch`), so they need no
/// special case here; the UI additionally shows the trust sheet for them.
ErrorMessage connectionErrorMessage(AppLocalizations l10n, AppError error) {
  if (error.category == ErrorCategory.authFailed &&
      error.debugDetail == needsCredentialsDetail) {
    return ErrorMessage(
      message: l10n.connErrorNeedsCredentialsMessage,
      hint: l10n.connErrorNeedsCredentialsHint,
    );
  }
  if (error.category == ErrorCategory.parseError &&
      error.debugDetail == 'invalid port') {
    return ErrorMessage(
      message: l10n.connErrorInvalidPortMessage,
      hint: l10n.connErrorInvalidPortHint,
    );
  }
  if (error.category == ErrorCategory.parseError &&
      error.debugDetail == 'host must be ascii') {
    return ErrorMessage(
      message: l10n.connErrorNonAsciiHostMessage,
      hint: l10n.connErrorNonAsciiHostHint,
    );
  }
  if (error.category == ErrorCategory.parseError &&
      _invalidInputDetails.contains(error.debugDetail)) {
    return ErrorMessage(
      message: l10n.connErrorInvalidInputMessage,
      hint: l10n.connErrorInvalidInputHint,
    );
  }
  return switch (error.category) {
    ErrorCategory.authFailed => ErrorMessage(
      message: l10n.connErrorAuthFailedMessage,
      hint: l10n.connErrorAuthFailedHint,
    ),
    ErrorCategory.timeout => ErrorMessage(
      message: l10n.connErrorTimeoutMessage,
      hint: l10n.connErrorTimeoutHint,
    ),
    ErrorCategory.tlsPinMismatch => ErrorMessage(
      message: l10n.connErrorTlsPinMismatchMessage,
      hint: l10n.connErrorTlsPinMismatchHint,
    ),
    ErrorCategory.tlsUntrusted => ErrorMessage(
      message: l10n.connErrorTlsUntrustedMessage,
      hint: l10n.connErrorTlsUntrustedHint,
    ),
    ErrorCategory.tlsExpired => ErrorMessage(
      message: l10n.connErrorTlsExpiredMessage,
      hint: l10n.connErrorTlsExpiredHint,
    ),
    ErrorCategory.cleartextRefused => ErrorMessage(
      message: l10n.connErrorCleartextRefusedMessage,
      hint: l10n.connErrorCleartextRefusedHint,
    ),
    ErrorCategory.unsupportedVersion => ErrorMessage(
      message: l10n.connErrorUnsupportedVersionMessage,
      hint: l10n.connErrorUnsupportedVersionHint,
    ),
    ErrorCategory.notFound => ErrorMessage(
      message: l10n.connErrorNotFoundMessage,
      hint: l10n.connErrorNotFoundHint,
    ),
    ErrorCategory.serverError => ErrorMessage(
      message: l10n.connErrorServerErrorMessage,
      hint: l10n.connErrorServerErrorHint,
    ),
    ErrorCategory.networkUnreachable => ErrorMessage(
      message: l10n.connErrorNetworkUnreachableMessage,
      hint: l10n.connErrorNetworkUnreachableHint,
    ),
    ErrorCategory.parseError => ErrorMessage(
      message: l10n.connErrorParseErrorMessage,
      hint: l10n.connErrorParseErrorHint,
    ),
    ErrorCategory.redirectRefused => ErrorMessage(
      message: l10n.connErrorRedirectRefusedMessage,
      hint: l10n.connErrorRedirectRefusedHint,
    ),
    ErrorCategory.responseTooLarge => ErrorMessage(
      message: l10n.connErrorResponseTooLargeMessage,
      hint: l10n.connErrorResponseTooLargeHint,
    ),
  };
}
