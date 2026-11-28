// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/shared/time/calendar_days.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The local calendar day (a UTC midnight, see `calendarDay`) that screens
/// showing "today" are on (the Dashboard's "today" and "tomorrow", the Radarr
/// calendar's "Today" header). It changes at local midnight, so a screen that
/// stays open does not keep yesterday's words: watch it to rebuild then.
///
/// The timer to the next midnight runs only while some screen says it is
/// visible ([setVisible]); with none visible there is no timer at all, and the
/// day catches up when one becomes visible again. Visibility is counted by
/// owner (like `SecureScreen`), so a hidden tab cannot stop the timer of the
/// visible one.
final currentDayProvider = NotifierProvider<CurrentDay, DateTime>(
  CurrentDay.new,
);

class CurrentDay extends Notifier<DateTime> {
  Timer? _timer;
  final Set<Object> _visibleOwners = {};

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    return _today();
  }

  DateTime _today() {
    final now = ref.read(clockProvider)();
    return calendarDay(now, now.timeZoneOffset);
  }

  /// Arms the midnight timer while any [owner] is visible, cancels it when
  /// none is.
  void setVisible(bool visible, {required Object owner}) {
    if (!visible) {
      // Never touches `state`, so it is safe at any time, even during a
      // build; the timer of an owner that is still visible keeps running.
      _visibleOwners.remove(owner);
      if (_visibleOwners.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
      return;
    }
    _visibleOwners.add(owner);
    _timer?.cancel();
    _timer = null;
    if (!ref.mounted) return;
    final today = _today();
    if (today != state) state = today;
    _arm();
  }

  void _arm() {
    final now = ref.read(clockProvider)();
    final next = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day + 1);
    // A second of slack, so the clock is surely past midnight when it fires.
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _timer = null;
      if (!ref.mounted || _visibleOwners.isEmpty) return;
      state = _today();
      _arm();
    });
  }
}
