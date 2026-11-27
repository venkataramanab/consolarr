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
