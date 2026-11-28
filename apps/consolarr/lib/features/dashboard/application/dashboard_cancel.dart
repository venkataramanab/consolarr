// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:dio/dio.dart';

/// Zone value that carries the [CancelToken] of the request group running.
final Object _tokenKey = Object();

/// A Dio that shares everything with [base] (options, adapter, transformer,
/// interceptors) but gives every request started inside [runCancellable] the
/// token of that call. Clients created once per connection (torrent sessions)
/// keep working: each call brings its own token.
///
/// The adapter is shared, not owned: only [base] is ever closed.
Dio cancellableDio(Dio base) {
  final dio = Dio(base.options.copyWith())
    ..httpClientAdapter = base.httpClientAdapter
    ..transformer = base.transformer;
  dio.interceptors
    ..clear()
    ..add(_TokenInterceptor())
    ..addAll(base.interceptors);
  return dio;
}

/// Runs [body] so that every request of a [cancellableDio] it starts (also
/// after an `await`) can be cancelled with [token].
T runCancellable<T>(CancelToken token, T Function() body) =>
    runZoned(body, zoneValues: {_tokenKey: token});

class _TokenInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = Zone.current[_tokenKey];
    if (token is CancelToken) options.cancelToken ??= token;
    handler.next(options);
  }
}
