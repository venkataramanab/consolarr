// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

/// Runs [body] and asserts it fails with a [TestFailure] whose message
/// matches [message]. (`expectLater(future, throwsA(...))` can't be used with
/// guarded WidgetTester calls.)
Future<void> expectTestFailure(
  Future<void> Function() body, {
  Matcher? message,
}) async {
  try {
    await body();
  } on TestFailure catch (e) {
    if (message != null) expect(e.message, message);
    return;
  }
  fail('Expected a TestFailure but the body completed normally.');
}
