// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Waits for a duration. Inject a recording or instant version in tests so
/// fault simulations never sleep in real time.
typedef DelayFunction = Future<void> Function(Duration duration);

Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

/// A network misbehaviour applied by [FaultInjectingAdapter].
///
/// [attempt] counts how many times the same `METHOD uri` has been requested
/// through the adapter (1 for the first request).
abstract class Fault {
  const Fault();

  /// Runs before the request reaches the inner adapter. May wait, throw a
  /// [DioException], or return a synthetic response (skipping the inner
  /// adapter).
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async => null;

  /// Wraps the real [response]; e.g. to slow or truncate its body.
  ResponseBody after(
    RequestOptions options,
    ResponseBody response,
    int attempt,
    DelayFunction delay,
  ) => response;
}

/// Adds [duration] of latency before the request is sent.
class LatencyFault extends Fault {
  const LatencyFault(this.duration);
  final Duration duration;

  @override
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async {
    await delay(duration);
    return null;
  }
}

/// Which timeout a [TimeoutFault] simulates.
enum TimeoutKind { connect, send, receive }

/// Fails with a Dio timeout. With [firstAttempts] set, only the first N
/// requests to the same endpoint time out (a retry then succeeds).
class TimeoutFault extends Fault {
  const TimeoutFault({this.kind = TimeoutKind.connect, this.firstAttempts});
  final TimeoutKind kind;
  final int? firstAttempts;

  @override
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async {
    if (firstAttempts != null && attempt > firstAttempts!) return null;
    const timeout = Duration(seconds: 30);
    throw switch (kind) {
      TimeoutKind.connect => DioException.connectionTimeout(
        timeout: timeout,
        requestOptions: options,
      ),
      TimeoutKind.send => DioException.sendTimeout(
        timeout: timeout,
        requestOptions: options,
      ),
      TimeoutKind.receive => DioException.receiveTimeout(
        timeout: timeout,
        requestOptions: options,
      ),
    };
  }
}

/// Drops the connection. Without [afterBytes] the request fails to connect;
/// with it, the response body is cut off after that many bytes.
class ConnectionDropFault extends Fault {
  const ConnectionDropFault({this.afterBytes});
  final int? afterBytes;

  @override
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async {
    if (afterBytes != null) return null;
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'connection dropped',
      error: const SocketException('connection dropped'),
    );
  }

  @override
  ResponseBody after(
    RequestOptions options,
    ResponseBody response,
    int attempt,
    DelayFunction delay,
  ) {
    final limit = afterBytes;
    if (limit == null) return response;
    Stream<Uint8List> truncated() async* {
      var sent = 0;
      await for (final chunk in response.stream) {
        final remaining = limit - sent;
        if (chunk.length >= remaining) {
          if (remaining > 0) yield Uint8List.sublistView(chunk, 0, remaining);
          throw const SocketException('connection dropped mid-body');
        }
        sent += chunk.length;
        yield chunk;
      }
      throw const SocketException('connection dropped mid-body');
    }

    return ResponseBody(
      truncated(),
      response.statusCode,
      headers: response.headers,
      statusMessage: response.statusMessage,
    );
  }
}

/// Answers the first [failFirst] requests to each endpoint with
/// [statusCode], then lets requests through (a flaky server).
class FlakyFault extends Fault {
  const FlakyFault({this.failFirst = 1, this.statusCode = 503});
  final int failFirst;
  final int statusCode;

  @override
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async {
    if (attempt > failFirst) return null;
    return ResponseBody.fromString('', statusCode);
  }
}

/// Delivers the response body in [chunkSize]-byte pieces, waiting
/// [chunkDelay] before each piece.
class SlowBodyFault extends Fault {
  const SlowBodyFault({required this.chunkSize, required this.chunkDelay});
  final int chunkSize;
  final Duration chunkDelay;

  @override
  ResponseBody after(
    RequestOptions options,
    ResponseBody response,
    int attempt,
    DelayFunction delay,
  ) {
    Stream<Uint8List> slow() async* {
      await for (final chunk in response.stream) {
        for (var i = 0; i < chunk.length; i += chunkSize) {
          await delay(chunkDelay);
          final end = i + chunkSize < chunk.length
              ? i + chunkSize
              : chunk.length;
          yield Uint8List.sublistView(chunk, i, end);
        }
      }
    }

    return ResponseBody(
      slow(),
      response.statusCode,
      headers: response.headers,
      statusMessage: response.statusMessage,
    );
  }
}

/// A Dio [HttpClientAdapter] that applies [faults] (in order) around an
/// [inner] adapter.
class FaultInjectingAdapter implements HttpClientAdapter {
  FaultInjectingAdapter({
    required this.inner,
    this.faults = const [],
    DelayFunction? delay,
  }) : _delay = delay ?? _realDelay;

  final HttpClientAdapter inner;
  final List<Fault> faults;
  final DelayFunction _delay;
  final Map<String, int> _attempts = {};

  /// Total requests seen.
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final key = '${options.method} ${options.uri}';
    final attempt = _attempts.update(key, (n) => n + 1, ifAbsent: () => 1);

    // Honour Dio's cancellation: injected waits end immediately and the
    // request fails with a cancel exception, like a real adapter would.
    Future<T> cancellable<T>(Future<T> work) =>
        _raceCancel(work, cancelFuture, options);
    Future<void> delay(Duration d) => cancellable(_delay(d));

    if (cancelFuture != null) {
      // A future that is already complete reports on the next microtask.
      var alreadyCancelled = false;
      unawaited(cancelFuture.then((_) => alreadyCancelled = true));
      await Future<void>.value();
      if (alreadyCancelled) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        );
      }
    }

    return cancellable(() async {
      for (final fault in faults) {
        final synthetic = await fault.before(options, attempt, delay);
        if (synthetic != null) return synthetic;
      }
      var response = await inner.fetch(options, requestStream, cancelFuture);
      for (final fault in faults) {
        response = fault.after(options, response, attempt, delay);
      }
      return response;
    }());
  }

  static Future<T> _raceCancel<T>(
    Future<T> work,
    Future<void>? cancelFuture,
    RequestOptions options,
  ) {
    if (cancelFuture == null) return work;
    final done = Completer<T>();
    unawaited(
      cancelFuture.then((_) {
        if (!done.isCompleted) {
          done.completeError(
            DioException.requestCancelled(
              requestOptions: options,
              reason: 'cancelled',
            ),
          );
        }
      }),
    );
    work.then(
      (v) {
        if (!done.isCompleted) done.complete(v);
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
    );
    return done.future;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// A minimal in-memory server for tests: answers every request with
/// [handler].
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.handler);

  /// Always replies 200 with [body] and a JSON content type.
  factory StubAdapter.json(String body) => StubAdapter(
    (_) => ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    ),
  );

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}
