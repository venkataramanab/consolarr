// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onTick] every [interval] while [active] and the app is in the
/// foreground. Stops when hidden or paused, and resumes on return. The loop is
/// a single timer, so it can never pile up requests.
class VisiblePoller extends StatefulWidget {
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
  State<VisiblePoller> createState() => _VisiblePollerState();
}

class _VisiblePollerState extends State<VisiblePoller>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (!widget.active || !_foreground) return;
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
