// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_dates.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The local calendar day (a UTC midnight, see `calendarDay`) the dashboard is
/// showing. "today" and "tomorrow" on the carousels follow it: it changes at
/// local midnight, so a dashboard that stays open does not keep yesterday's
/// words.
///
/// The timer to the next midnight runs only while the screen says it is
/// visible ([setVisible]); a hidden dashboard has no timer at all and catches
/// up when it becomes visible again.
final dashboardDayProvider = NotifierProvider<DashboardDay, DateTime>(
  DashboardDay.new,
);

class DashboardDay extends Notifier<DateTime> {
  Timer? _timer;
  bool _visible = false;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    return _today();
  }

  DateTime _today() {
    final now = ref.read(clockProvider)();
    return calendarDay(now, now.timeZoneOffset);
  }

  /// Arms the midnight timer while visible, cancels it while hidden.
  void setVisible(bool visible) {
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    if (!visible || !ref.mounted) return;
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
      if (!ref.mounted || !_visible) return;
      state = _today();
      _arm();
    });
  }
}
