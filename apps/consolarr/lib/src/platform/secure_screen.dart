// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

/// Marks the app window as secure (no screenshots or screen recording, hidden
/// in the recents list) while something needs it.
///
/// Requests are **reference counted by owner**: the window is secure while at
/// least one owner has asked for it. The app lock and the "block screenshots"
/// switch are one owner, each revealed secret field is part of another. Turning
/// the lock off therefore cannot clear the flag while a server editor still
/// shows a revealed secret, and the other way round.
abstract interface class SecureScreen {
  /// The owner used when a caller passes none.
  static const Object anonymousOwner = Object();

  /// Sets whether [owner] needs the window secure. The effective flag is on
  /// while any owner needs it.
  Future<void> setSecure({required bool secure, Object? owner});
}

/// The owner bookkeeping both implementations share.
mixin SecureOwners {
  final Set<Object> _owners = {};

  /// Whether any owner currently needs the window secure.
  bool get isSecure => _owners.isNotEmpty;

  /// How many owners need the window secure.
  int get ownerCount => _owners.length;

  /// Applies the request and returns the effective flag.
  bool applyOwner(Object? owner, {required bool secure}) {
    final key = owner ?? SecureScreen.anonymousOwner;
    if (secure) {
      _owners.add(key);
    } else {
      _owners.remove(key);
    }
    return _owners.isNotEmpty;
  }
}

/// Android `FLAG_SECURE` through the `consolarr/secure_screen` channel. One
/// instance per provider scope (no process-wide state).
class PlatformSecureScreen with SecureOwners implements SecureScreen {
  static const _channel = MethodChannel('consolarr/secure_screen');

  @override
  Future<void> setSecure({required bool secure, Object? owner}) async {
    final before = isSecure;
    final effective = applyOwner(owner, secure: secure);
    // Only a real change reaches the platform.
    if (effective == before) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': effective});
    } on MissingPluginException {
      // Not on Android (tests, desktop): nothing to protect.
    }
  }
}

/// Records calls; for tests. `calls` holds the effective flag after every
/// request.
class RecordingSecureScreen with SecureOwners implements SecureScreen {
  final List<bool> calls = [];

  @override
  bool get isSecure => super.isSecure;

  @override
  Future<void> setSecure({required bool secure, Object? owner}) async =>
      calls.add(applyOwner(owner, secure: secure));
}
