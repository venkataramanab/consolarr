// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

/// Marks the app window as secure (no screenshots or screen recording, hidden
/// in the recents list) while secrets are visible.
abstract interface class SecureScreen {
  Future<void> setSecure({required bool secure});
}

/// Android `FLAG_SECURE` through the `consolarr/secure_screen` channel.
class PlatformSecureScreen implements SecureScreen {
  const PlatformSecureScreen();

  static const _channel = MethodChannel('consolarr/secure_screen');

  @override
  Future<void> setSecure({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Not on Android (tests, desktop): nothing to protect.
    }
  }
}

/// Records calls; for tests.
class RecordingSecureScreen implements SecureScreen {
  final List<bool> calls = [];

  bool get isSecure => calls.isNotEmpty && calls.last;

  @override
  Future<void> setSecure({required bool secure}) async => calls.add(secure);
}
