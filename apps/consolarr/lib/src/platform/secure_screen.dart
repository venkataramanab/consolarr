// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

/// Marks the app window as secure (no screenshots or screen recording, hidden
/// in the recents list) while secrets are visible.
abstract interface class SecureScreen {
  Future<void> setSecure({required bool secure});
}

/// Android `FLAG_SECURE` through the `consolarr/secure_screen` channel.
///
/// The window also has a **baseline** the app lock and the "block
/// screenshots" switch require ([setBaseline]): a screen that asks for
/// `secure: false` (for example the server editor once its secrets are hidden
/// again) never removes the flag while the baseline is on.
class PlatformSecureScreen implements SecureScreen {
  const PlatformSecureScreen();

  static const _channel = MethodChannel('consolarr/secure_screen');

  static bool _baseline = false;

  /// Whether the whole window must stay secure regardless of single screens.
  static bool get baseline => _baseline;

  /// Sets the baseline (no channel call). The app lock gate sets it, then
  /// asks the `SecureScreen` seam to apply the window state.
  static void setBaseline({required bool secure}) => _baseline = secure;

  @override
  Future<void> setSecure({required bool secure}) => _apply(secure || _baseline);

  Future<void> _apply(bool secure) async {
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
