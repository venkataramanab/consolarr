// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/shared/polling/poll_scheduler.dart';
import 'package:consolarr/shared/polling/poll_visibility.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Calls [onTick] every [interval] while [active], the app is in the
/// foreground, the widget is on screen and the app is not locked.
///
/// "On screen" means tickers are enabled (`TickerMode`: a tab that is not
/// selected, or a branch under a lock, turns them off) and the enclosing route
/// is the current one (nothing pushed on top). In every other state the timer
/// is cancelled, not left to tick and skip, and it is started again when the
/// state changes back. The loop is a single timer with a busy flag, so it can
/// never pile up requests.
class VisiblePoller extends ConsumerStatefulWidget {
  const VisiblePoller({
    required this.active,
    required this.onTick,
    required this.child,
    this.interval = const Duration(seconds: 10),
    super.key,
  });

  final bool active;
  final Duration interval;
  final Future<void> Function() onTick;
  final Widget child;

  @override
  ConsumerState<VisiblePoller> createState() => _VisiblePollerState();
}

class _VisiblePollerState extends ConsumerState<VisiblePoller>
    with WidgetsBindingObserver, PollVisibility<VisiblePoller> {
  late final PollScheduler _scheduler = PollScheduler(
    interval: widget.interval,
    isVisible: () => widget.active && isVisible,
    tick: () async {
      await widget.onTick();
      return true;
    },
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void onVisibilityChanged({required bool visible}) => _sync();

  @override
  void didUpdateWidget(VisiblePoller old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.interval != widget.interval) {
      _scheduler.setInterval(widget.interval);
      _sync();
    }
  }

  /// A hidden or inactive poller has no timer at all; becoming visible again
  /// waits one full interval before the first tick.
  void _sync() {
    if (widget.active && isVisible) {
      _scheduler.start();
    } else {
      _scheduler.dispose();
    }
  }

  @override
  void dispose() {
    _scheduler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
