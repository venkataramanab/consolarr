// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/platform/secure_screen.dart';

/// Keeps the window secure while any secret field is revealed.
///
/// Call [update] from every field's `onRevealChanged` and [dispose] when the
/// screen goes away (that always clears the flag).
class RevealTracker {
  RevealTracker(this._screen);

  final SecureScreen _screen;
  final Set<Object> _revealed = {};
  bool _secure = false;

  bool get isSecure => _secure;

  void update(Object field, bool revealed) {
    if (revealed) {
      _revealed.add(field);
    } else {
      _revealed.remove(field);
    }
    _apply();
  }

  void _apply() {
    final want = _revealed.isNotEmpty;
    if (want == _secure) return;
    _secure = want;
    _screen.setSecure(secure: want, owner: this);
  }

  void dispose() {
    _revealed.clear();
    _apply();
  }
}
