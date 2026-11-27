// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/lock_controller.dart';
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
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;
  bool _locked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = ref.read(appLockedProvider);
    ref.listenManual(appLockedProvider, (_, locked) {
      _locked = locked;
      _sync();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    _sync();
  }

  @override
  void didUpdateWidget(VisiblePoller old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.interval != widget.interval) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.active || !_foreground || !_visible || _locked) return;
    _timer = Timer.periodic(widget.interval, (_) async {
      if (_busy) return;
      _busy = true;
      try {
        await widget.onTick();
      } finally {
        _busy = false;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
