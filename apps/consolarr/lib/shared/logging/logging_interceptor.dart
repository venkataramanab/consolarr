// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/logging/route_shape.dart';
import 'package:dio/dio.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

/// `RequestOptions.extra` flag the artwork loader sets on every attempt of one
/// image (the listed file, its resized variant, the fallbacks): a 404 of such
/// an attempt is not logged by the interceptor, the loader logs the whole
/// attempt once ([LoggingInterceptor.artworkMissing]).
const artworkChainKey = 'consolarr.artwork.chain';

/// Logs each request of a server connection as a route shape plus a status or
/// an [ErrorCategory], nothing else (SET-04 diagnostics).
///
/// * Success, at debug: `GET api·v3·movie·{id} -> 200, 12ms`.
/// * Failure, at warning: `GET api·v3·movie failed category=auth_failed
///   status=401, 12ms`.
///
/// Routes join their segments with `·` and contain only words from a closed
/// vocabulary (see [routeShape]): the diagnostics scrubber would turn a `/`
/// path or a dotted name into `[REDACTED]`, so a line never has either.
///
/// What it never touches: the host, port, userinfo, query string, headers,
/// request or response bodies, titles or credentials. It reads only the method,
/// the path (reduced by [routeShape]), the status code and the clock, so it
/// is cheap enough to stay attached to every connection.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(
    this._logger, {
    this.pathPrefix = '',
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? _stopwatchMs;

  final AppLogger _logger;

  /// The server's path prefix, removed from logged routes.
  final String pathPrefix;
  final int Function() _nowMs;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int _stopwatchMs() => _stopwatch.elapsedMilliseconds;

  static const _startKey = 'consolarr.log.start';
  static const _methods = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'};

  /// The interceptor attached to [dio], or `null`. Lets the artwork loader log
  /// a rejected image without every call site passing a logger along.
  static LoggingInterceptor? of(Dio dio) {
    for (final i in dio.interceptors) {
      if (i is LoggingInterceptor) return i;
    }
    return null;
  }

  /// Debug lines are only worth building when something would keep them.
  bool get _wantsDebug =>
      _logger.minLevel == LogLevel.debug ||
      (_logger.diagnostics?.enabled ?? false);

  /// Artwork is fetched in bulk (a poster per row): its successes are not
  /// logged, and a missing image (404) is only a debug line.
  static bool _isArtwork(String shape) {
    final root = shape.split(routeSeparator).first;
    return root == 'MediaCover' || root == 'MediaCoverProxy';
  }

  String _shape(RequestOptions o) =>
      routeShape(o.uri.path, pathPrefix: pathPrefix);

  String _route(RequestOptions o) =>
      '${_method(o.method)} ${routeShape(o.uri.path, pathPrefix: pathPrefix)}';

  static String _method(String m) {
    final upper = m.toUpperCase();
    return _methods.contains(upper) ? upper : 'REQUEST';
  }

  int _elapsed(RequestOptions o) {
    final start = o.extra[_startKey];
    return start is int ? _nowMs() - start : 0;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = _nowMs();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final o = response.requestOptions;
    if (_wantsDebug && !_isArtwork(_shape(o))) {
      _logger.debug(
        '${_route(o)} -> ${response.statusCode ?? 0}, ${_elapsed(o)}ms',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    // Cancelling is the caller's choice (a list scrolled away), not a failure.
    if (err.type == DioExceptionType.cancel) {
      handler.next(err);
      return;
    }
    final category = appErrorFromDio(err).category.code;
    final status = err.response?.statusCode;
    final line =
        '${_route(o)} failed category=$category'
        '${status == null ? '' : ' status=$status'}, ${_elapsed(o)}ms';
    if (_isArtwork(_shape(o)) && status == 404) {
      if (o.extra[artworkChainKey] != true && _wantsDebug) _logger.debug(line);
    } else {
      _logger.warning(line);
    }
    handler.next(err);
  }

  /// An artwork response that was not a supported image (an HTML login page,
  /// a proxy error, an empty body). Logs the route, the status and a coarse
  /// body type; never the URL, query or the server's own text.
  void artworkRejected(
    Uri uri, {
    required int? status,
    required String? contentType,
    required bool isEmpty,
  }) {
    final type = isEmpty
        ? 'empty'
        : (contentType ?? '').toLowerCase().contains('html')
        ? 'html'
        : (contentType ?? '').toLowerCase().contains('json')
        ? 'json'
        : 'other';
    _logger.warning(
      'artwork GET ${routeShape(uri.path, pathPrefix: pathPrefix)} rejected '
      'category=not_an_image status=${status ?? 0} type=$type',
    );
  }

  /// Every candidate of one artwork image answered 404 (for example a poster
  /// and its resized variant): one debug line for the whole attempt, with the
  /// route of the first candidate and how many were tried.
  void artworkMissing(Uri uri, {required int tried}) {
    if (!_wantsDebug) return;
    _logger.debug(
      'artwork GET ${routeShape(uri.path, pathPrefix: pathPrefix)} missing '
      'category=not_found status=404 tried=$tried',
    );
  }
}
