// SPDX-License-Identifier: GPL-3.0-or-later

/// `RequestOptions.extra` key that overrides [HttpLimits.maxResponseBytes] for
/// one request (for example larger limits for artwork).
const maxResponseBytesKey = 'consolarr.maxResponseBytes';

/// Timeouts and size limits applied to every request of a secure client.
class HttpLimits {
  const HttpLimits({
    this.connectTimeout = const Duration(seconds: 10),
    this.sendTimeout = const Duration(seconds: 20),
    this.receiveTimeout = const Duration(seconds: 30),
    this.maxResponseBytes = 64 * 1024 * 1024,
    this.maxRedirects = 5,
  });

  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;

  /// Responses larger than this fail with `response_too_large`; checked
  /// against `Content-Length` and again while streaming.
  final int maxResponseBytes;

  /// Redirect hops followed before the request is refused.
  final int maxRedirects;
}
