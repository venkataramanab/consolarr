// SPDX-License-Identifier: GPL-3.0-or-later

/// `RequestOptions.extra` key that overrides [HttpLimits.maxResponseBytes] for
/// one request (for example larger limits for artwork).
const maxResponseBytesKey = 'consolarr.maxResponseBytes';

/// `Response.extra` key under which the secure adapter reports the URI of the
/// **final hop** (a [Uri]). The adapter follows redirects itself, so
/// `Response.realUri` always shows the first URI; clients that capture a
/// session (cookie, session id) must compare this one with the configured
/// server origin first.
const finalUriExtraKey = 'consolarr.finalUri';

/// Timeouts and size limits applied to every request of a secure client.
class HttpLimits {
  const HttpLimits({
    this.connectTimeout = const Duration(seconds: 10),
    this.sendTimeout = const Duration(seconds: 20),
    this.receiveTimeout = const Duration(seconds: 30),
    this.requestDeadline = const Duration(seconds: 60),
    this.maxResponseBytes = 16 * 1024 * 1024,
    this.maxRedirects = 5,
  });

  final Duration connectTimeout;
  final Duration sendTimeout;

  /// Per-chunk idle timeout only: a server that drips one byte at a time keeps
  /// resetting it, so it is not a bound on the request.
  final Duration receiveTimeout;

  /// Upper bound for a whole request: from the first connection attempt (every
  /// redirect hop included) until the last body byte. Exceeding it fails with
  /// `timeout`.
  final Duration requestDeadline;

  /// Responses larger than this fail with `response_too_large`; checked
  /// against `Content-Length` and again while streaming. Callers that really
  /// need more (artwork) raise it per request with [maxResponseBytesKey].
  final int maxResponseBytes;

  /// Redirect hops followed before the request is refused.
  final int maxRedirects;
}
