// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:test_harness/test_harness.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadBundledFonts();
  await testMain();
}
