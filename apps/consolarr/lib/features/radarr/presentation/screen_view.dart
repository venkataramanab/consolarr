// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// Reports `screen_viewed` once, after the first frame of the host.
class RadarrScreenView extends ConsumerStatefulWidget {
  const RadarrScreenView({
    required this.screen,
    required this.child,
    super.key,
  });

  final ScreenName screen;
  final Widget child;

  @override
  ConsumerState<RadarrScreenView> createState() => _State();
}

class _State extends ConsumerState<RadarrScreenView> {
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
