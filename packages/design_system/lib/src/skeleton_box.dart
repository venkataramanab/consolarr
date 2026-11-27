// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/effects.dart';
import 'package:design_system/src/motion.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:material_ui/material_ui.dart';

/// Placeholder block for loading layouts. Soft shimmer; completely static
/// (no ticker) when motion is reduced. Hidden from screen readers.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(ConsolarrRadii.sm),
    ),
    super.key,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ConsolarrEffects.of(context).animate) {
      _controller ??= AnimationController(
        vsync: this,
        duration: ConsolarrMotion.shimmer,
      )..repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final controller = _controller;
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: controller == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: roles.track,
                  borderRadius: widget.borderRadius,
                ),
              )
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: [roles.track, roles.raised, roles.track],
                      stops: const [0, 0.5, 1],
                      transform: _Slide(controller.value),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * (t * 2 - 1);
    return Matrix4.translationValues(
      textDirection == TextDirection.rtl ? -dx : dx,
      0,
      0,
    );
  }
}
