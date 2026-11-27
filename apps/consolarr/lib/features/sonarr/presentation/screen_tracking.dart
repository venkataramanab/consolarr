// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// Reports `screen_viewed` once when [child] first builds (for the child
/// routes and sheets of the Sonarr area; the shell reports the tabs).
class TrackScreen extends ConsumerStatefulWidget {
  const TrackScreen({required this.screen, required this.child, super.key});

  final ScreenName screen;
  final Widget child;

  @override
  ConsumerState<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends ConsumerState<TrackScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(eventTrackerProvider)
          .track(ScreenViewedEvent(screen: widget.screen));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
