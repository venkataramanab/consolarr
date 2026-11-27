// SPDX-License-Identifier: GPL-3.0-or-later

/// Stable, user-meaningful failure categories.
///
/// UI maps a category to localized copy; the wire [code] is stable and safe
/// to log (it never contains secrets, URLs or titles).
enum ErrorCategory {
  authFailed('auth_failed'),
  timeout('timeout'),
  tlsPinMismatch('tls_pin_mismatch'),
  cleartextRefused('cleartext_refused'),
  unsupportedVersion('unsupported_version'),
  notFound('not_found'),
  serverError('server_error'),
  networkUnreachable('network_unreachable'),
  parseError('parse_error'),
  tlsUntrusted('tls_untrusted'),
  tlsExpired('tls_expired'),
  redirectRefused('redirect_refused'),
  responseTooLarge('response_too_large');

  const ErrorCategory(this.code);

  /// Stable snake_case identifier.
  final String code;

  /// Looks up a category by its [code], or `null` if unknown.
  static ErrorCategory? fromCode(String code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return null;
  }
}

/// A typed, secret-free application error.
///
/// [debugDetail] is developer-facing only. It must never contain secrets,
/// credentials, URLs with keys or media titles, and is never shown in UI.
class AppError implements Exception {
  const AppError(this.category, {this.debugDetail});

  final ErrorCategory category;
  final String? debugDetail;

  @override
  bool operator ==(Object other) =>
      other is AppError &&
      other.category == category &&
      other.debugDetail == debugDetail;

  @override
  int get hashCode => Object.hash(category, debugDetail);

  @override
  String toString() => 'AppError(${category.code})';
}

/// Failures after which cached or last-good data is shown (with an offline
/// marker) instead of an error: the server is not reachable or not healthy.
///
/// Everything else is shown as such and never hidden behind old data:
/// `auth_failed`, `unsupported_version`, `cleartext_refused`, redirects and
/// every TLS category (a pin mismatch must block).
const Set<ErrorCategory> kOfflineFallbackCategories = {
  ErrorCategory.networkUnreachable,
  ErrorCategory.timeout,
  ErrorCategory.serverError,
  ErrorCategory.notFound,
  ErrorCategory.parseError,
  ErrorCategory.responseTooLarge,
};
