// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Folds everything that decides whether a poll may run into one flag:
///
/// * the app is in the foreground (lifecycle `resumed`);
/// * the widget is on screen: tickers are enabled (`TickerMode`: an unselected
///   tab, or a branch under a lock, turns them off) and the enclosing route is
///   the current one (nothing pushed on top);
/// * the app is not locked (`appLockedProvider`, patterns section 7).
///
/// Mix into a `ConsumerState` that also mixes in `WidgetsBindingObserver` and
/// implement [onVisibilityChanged]; it is called only when [isVisible]
/// actually changes. A poller must cancel its timer when it turns false and
/// start it again when it turns true (never tick and skip).
mixin PollVisibility<W extends ConsumerStatefulWidget>
    on ConsumerState<W>, WidgetsBindingObserver {
  bool _foreground = true;
  bool _onScreen = true;
  bool _locked = false;
  bool _lastVisible = true;

  bool get isVisible => _foreground && _onScreen && !_locked;

  /// Called after [isVisible] changed to [visible].
  void onVisibilityChanged({required bool visible});

  void _notify() {
    final now = isVisible;
    if (now == _lastVisible) return;
    _lastVisible = now;
    onVisibilityChanged(visible: now);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = ref.read(appLockedProvider);
    _lastVisible = isVisible;
    ref.listenManual(appLockedProvider, (_, locked) {
      _locked = locked;
      _notify();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onScreen =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _notify();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
