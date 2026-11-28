// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// Reports `screen_viewed` once, after the first frame of its child (sheets).
class TorrentScreenView extends ConsumerStatefulWidget {
  const TorrentScreenView({
    required this.screen,
    required this.child,
    super.key,
  });

  final ScreenName screen;
  final Widget child;

  @override
  ConsumerState<TorrentScreenView> createState() => _TorrentScreenViewState();
}

class _TorrentScreenViewState extends ConsumerState<TorrentScreenView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(eventTrackerProvider)
            .track(ServersScreenViewedEvent(screen: widget.screen));
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
