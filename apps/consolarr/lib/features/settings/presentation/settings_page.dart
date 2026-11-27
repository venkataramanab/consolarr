// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:consolarr/src/providers.dart';

/// Reports `screen_viewed` once when [child] first appears. Settings and
/// diagnostics screens wrap themselves in this.
class ScreenTracker extends ConsumerStatefulWidget {
  const ScreenTracker({required this.screen, required this.child, super.key});

  final ScreenName screen;
  final Widget child;

  @override
  ConsumerState<ScreenTracker> createState() => _ScreenTrackerState();
}

class _ScreenTrackerState extends ConsumerState<ScreenTracker> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(eventTrackerProvider)
            .track(ScreenViewedEvent(screen: widget.screen));
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A settings sub-screen: app bar with back button, a scrolling list padded
/// by the floating navigation bar's measured height (the shell reports it
/// through `MediaQuery.padding.bottom`).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.title,
    required this.screen,
    required this.children,
    this.actions = const [],
    super.key,
  });

  final String title;
  final ScreenName screen;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ScreenTracker(
      screen: screen,
      child: Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              ConsolarrSpacing.gutter,
              ConsolarrSpacing.md,
              ConsolarrSpacing.gutter,
              ConsolarrSpacing.lg + bottom,
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}
