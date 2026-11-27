// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Replays canned responses and records every request.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  /// Replies to every request with [status] and [body].
  factory FakeAdapter.fixed(String body, {int status = 200}) =>
      FakeAdapter((_) => FakeAdapter.reply(body, status: status));

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  static ResponseBody reply(String body, {int status = 200}) =>
      ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  /// A body that delivers [prefix] and then fails like a dropped connection.
  static ResponseBody dropped(String prefix) {
    Stream<Uint8List> body() async* {
      yield Uint8List.fromList(utf8.encode(prefix));
      throw const SocketException('connection dropped mid-body');
    }

    return ResponseBody(body(), 200);
  }

  @override
  void close({bool force = false}) {}
}

/// A Dio with [adapter] and the given base URL.
Dio dioWith(FakeAdapter adapter, {String base = 'https://sonarr.example'}) {
  final dio = Dio(BaseOptions(baseUrl: base));
  dio.httpClientAdapter = adapter;
  return dio;
}
