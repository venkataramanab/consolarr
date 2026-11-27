// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:isolate';

/// Runs [computation], possibly on another isolate. Inject an inline version
/// in tests.
typedef ParseRunner = Future<T> Function<T>(T Function() computation);

/// The default [ParseRunner]: a short-lived isolate.
Future<T> isolateRunner<T>(T Function() computation) =>
    Isolate.run(computation);

/// Bodies larger than this are parsed off the UI isolate.
const isolateThresholdBytes = 64 * 1024;

/// Parses [body] with [parse], off the UI isolate when it is large.
///
/// Top level on purpose: the closure given to [runner] captures only [body]
/// and [parse] (which must be top-level or static), never a client (its
/// Dio/HttpClient cannot be sent to another isolate). Shared by all torrent
/// clients.
Future<T> parseOffIsolate<T>(
  ParseRunner runner,
  String body,
  T Function(String) parse,
) => body.length > isolateThresholdBytes
    ? runner(() => parse(body))
    : Future.value(parse(body));
