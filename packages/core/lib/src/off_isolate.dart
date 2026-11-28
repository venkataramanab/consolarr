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
/// Top level on purpose: the closure handed to [runner] captures only [body]
/// and [parse], never `this`. A closure written inside a client method drags
/// the whole client (its Dio/HttpClient cannot be sent to another isolate)
/// into the isolate message, `Isolate.run` throws, and every list over the
/// threshold would show as "offline". [parse] must therefore be a top-level
/// function or a static tear-off, never an instance method.
Future<T> parseOffIsolate<T>(
  ParseRunner runner,
  String body,
  T Function(String) parse,
) => body.length > isolateThresholdBytes
    ? runner(() => parse(body))
    : Future.value(parse(body));
