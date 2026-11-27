// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';

/// What to do with one redirect response (SRV-08).
sealed class RedirectDecision {
  const RedirectDecision();
}

/// Follow the redirect.
final class RedirectFollow extends RedirectDecision {
  const RedirectFollow({required this.keepHeaders, required this.toGet});

  /// Same origin: request headers (credentials) may be forwarded. Otherwise
  /// only [stripUnsafeHeaders] output is sent.
  final bool keepHeaders;

  /// The follow-up request becomes a body-less GET.
  final bool toGet;
}

/// Refuse with a typed, user-explainable error.
final class RedirectRefuse extends RedirectDecision {
  const RedirectRefuse(this.error);
  final AppError error;
}

const _refuse = RedirectRefuse(AppError(ErrorCategory.redirectRefused));

/// Decides a redirect from [from] to [to].
///
/// * only http(s) targets;
/// * https to http is never followed;
/// * an http target must be the profile's own host and the server must have
///   the cleartext opt-in;
/// * same scheme, host and port keeps headers, anything else is followed with
///   credentials stripped;
/// * non GET/HEAD requests follow only 301/302/303 (as body-less GET).
RedirectDecision decideRedirect({
  required Uri from,
  required Uri to,
  required int status,
  required String method,
  required String profileHost,
  required bool allowCleartext,
}) {
  if (to.scheme != 'http' && to.scheme != 'https') return _refuse;
  if (from.scheme == 'https' && to.scheme == 'http') return _refuse;
  if (to.scheme == 'http') {
    if (to.host.toLowerCase() != profileHost.toLowerCase()) return _refuse;
    if (!allowCleartext) {
      return const RedirectRefuse(AppError(ErrorCategory.cleartextRefused));
    }
  }
  final upper = method.toUpperCase();
  final safe = upper == 'GET' || upper == 'HEAD';
  if (!safe && status != 301 && status != 302 && status != 303) return _refuse;
  final sameOrigin =
      from.scheme == to.scheme &&
      from.host.toLowerCase() == to.host.toLowerCase() &&
      from.port == to.port;
  return RedirectFollow(keepHeaders: sameOrigin, toGet: !safe);
}

const _safeHeaders = {
  'accept',
  'accept-encoding',
  'user-agent',
  'content-type',
};

/// Copy of [headers] with everything but a small allowlist removed
/// (Authorization, Cookie, API keys and custom headers must never follow a
/// cross-origin redirect).
Map<String, dynamic> stripUnsafeHeaders(Map<String, dynamic> headers) => {
  for (final e in headers.entries)
    if (_safeHeaders.contains(e.key.toLowerCase())) e.key: e.value,
};
