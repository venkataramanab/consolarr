// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/logging/route_shape.dart';
import 'package:dio/dio.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

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
    if (_wantsDebug) {
      final o = response.requestOptions;
      _logger.debug(
        '${_route(o)} -> ${response.statusCode ?? 0}, ${_elapsed(o)}ms',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    final category = appErrorFromDio(err).category.code;
    final status = err.response?.statusCode;
    _logger.warning(
      '${_route(o)} failed category=$category'
      '${status == null ? '' : ' status=$status'}, ${_elapsed(o)}ms',
    );
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
}
