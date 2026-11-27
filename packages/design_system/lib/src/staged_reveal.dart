// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:design_system/src/effects.dart';
import 'package:design_system/src/motion.dart';
import 'package:material_ui/material_ui.dart';

/// A subtle fade and rise that plays **once per [revealKey]**, staggered by
/// [order] (0 first), and does nothing under reduced motion (system setting
/// or the in-app override).
///
/// Give every item of one list or screen the same [revealKey] (for example
/// `'sonarr.library'`) and its position as [order]. The key is remembered for
/// the life of the process, so coming back to the screen, rebuilding it or
/// scrolling an item into view later shows the content immediately.
///
/// ```dart
/// StagedReveal(
///   revealKey: 'settings.hub',
///   order: index,
///   child: SettingsSection(title: 'Display', children: rows),
/// )
/// ```
class StagedReveal extends StatefulWidget {
  const StagedReveal({
    required this.child,
    required this.revealKey,
    this.order = 0,
    super.key,
  });

  final Widget child;

  /// Items sharing a key reveal together, once.
  final Object revealKey;

  /// Position in the stagger; later items start a little later.
  final int order;

  /// Forgets every played key (tests).
  static void resetForTesting() => _played.clear();

  static final Set<Object> _played = <Object>{};

  @override
  State<StagedReveal> createState() => _StagedRevealState();
}

class _StagedRevealState extends State<StagedReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _decided = false;

  static const _step = Duration(milliseconds: 40);
  static const _maxOrder = 8;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final animate = ConsolarrEffects.of(context).animate;
    if (!animate || StagedReveal._played.contains(widget.revealKey)) return;
    final delay = _step * math.min(widget.order, _maxOrder);
    final total = ConsolarrMotion.standard + delay;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    // Siblings built in the same frame all see the key as unplayed; mark it
    // afterwards so later arrivals show immediately.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => StagedReveal._played.add(widget.revealKey),
    );
    controller.forward().whenComplete(() {
      if (mounted) setState(() => _controller = null);
      controller.dispose();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final delay = _step * math.min(widget.order, _maxOrder);
    final start = delay.inMicroseconds / controller.duration!.inMicroseconds;
    final curve = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: ConsolarrMotion.enterCurve),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}
