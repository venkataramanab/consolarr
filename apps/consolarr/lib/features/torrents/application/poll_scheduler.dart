// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

/// The longest wait between polls while the server keeps failing.
const maxPollBackoff = Duration(seconds: 60);

/// After this many failures in a row the list is shown as offline (the
/// scheduler keeps trying, slowly).
const pollFailuresUntilOffline = 3;

/// The wait before the next poll: [base] doubling with every failure in a row
/// up to [maxPollBackoff] (never below [base]).
Duration pollDelay(Duration base, int failures) {
  if (failures <= 0) return base;
  final capped = failures > 10 ? 10 : failures;
  final delay = base * (1 << capped);
  final limit = maxPollBackoff > base ? maxPollBackoff : base;
  return delay > limit ? limit : delay;
}

/// Polls with a delay that follows [pollDelay]. A tick runs only while
/// [isVisible] is true (the app is resumed and the screen is on top); a hidden
/// scheduler keeps its timer but does no work, so nothing hammers the server
/// or the battery.
class PollScheduler {
  PollScheduler({
    required Duration interval,
    required this.tick,
    required this.isVisible,
  }) : _interval = interval;

  final Future<bool> Function() tick;
  final bool Function() isVisible;

  Duration _interval;
  Timer? _timer;
  int _failures = 0;
  bool _running = false;
  bool _disposed = false;

  /// Failures in a row since the last success.
  int get failures => _failures;

  Duration get nextDelay => pollDelay(_interval, _failures);

  /// Starts (or restarts) the schedule; the first tick comes after one delay.
  void start() {
    _disposed = false;
    _schedule();
  }

  /// Changes the base interval and restarts the wait.
  void setInterval(Duration interval) {
    _interval = interval;
    if (!_disposed) _schedule();
  }

  /// Polls now (for example when the app returns to the foreground) and
  /// restarts the wait; the failure count is kept.
  Future<void> pollNow() async {
    if (_disposed) return;
    _timer?.cancel();
    await _run();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(nextDelay, _fire);
  }

  Future<void> _fire() async {
    if (_disposed) return;
    if (!isVisible()) {
      _schedule();
      return;
    }
    await _run();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      final ok = await tick();
      _failures = ok ? 0 : _failures + 1;
    } finally {
      _running = false;
      if (!_disposed) _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
