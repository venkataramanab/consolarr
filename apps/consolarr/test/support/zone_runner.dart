// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs a plain Dart [script] with the process time zone set to [zone], and
/// fails the test when it exits non-zero.
///
/// `DateTime.toLocal()` follows the zone the process was *started* in, so a
/// test cannot change it from inside: it starts a child process with `TZ` set
/// instead. This works on Linux and macOS (CI's runner is Linux) and needs the
/// zone database (`/usr/share/zoneinfo`); the script is given [expectedHours]
/// (the zone's January offset) and must check it first, so a runner without
/// the zone fails loudly instead of quietly testing UTC.
///
/// [script] is a path relative to the app (for example
/// `test/radarr/zones/zone_checks.dart`); it may import `package:` code that
/// does not need Flutter, and exits non-zero (an uncaught error) to fail.
Future<void> runUnderZone({
  required String zone,
  required int expectedHours,
  required String script,
}) async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final dart = root == null ? 'dart' : '$root/bin/dart';
  final result = await Process.run(
    dart,
    ['run', script, '$expectedHours'],
    environment: {'TZ': zone},
    includeParentEnvironment: true,
  );
  expect(
    result.exitCode,
    0,
    reason: 'under TZ=$zone\n${result.stdout}\n${result.stderr}',
  );
}
