// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show ImageFilter;

import 'package:design_system/src/blur_levels.dart';
import 'package:design_system/src/effects.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/roles_context.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// A bar that floats over scrolling content: frosted glass (blur plus a
/// strong tint) when [ConsolarrEffects.useGlass], a solid chrome surface with
/// a hairline border otherwise.
class GlassBar extends StatelessWidget {
  const GlassBar({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = ConsolarrRadii.bar,
    this.blur = ConsolarrBlur.medium,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final glass = ConsolarrEffects.of(context).useGlass && blur > 0;
    final content = Padding(padding: padding, child: child);
    if (!glass) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: roles.chrome,
          borderRadius: borderRadius,
          border: Border.all(color: roles.track),
        ),
        child: content,
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: roles.chrome.withValues(alpha: ConsolarrBlur.barTintOpacity),
            borderRadius: borderRadius,
            border: Border.all(color: roles.track.withValues(alpha: 0.6)),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Reports the laid-out height of [child] into [height], so a screen can pad
/// its scrolling content by the measured bar height.
class MeasuredBarHeight extends SingleChildRenderObjectWidget {
  const MeasuredBarHeight({
    required this.height,
    required Widget super.child,
    super.key,
  });

  final ValueNotifier<double> height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(height);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.notifier = height;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.notifier);

  ValueNotifier<double> notifier;
  double _last = -1;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    // Never notify during layout; schedule for after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && notifier.value != h) notifier.value = h;
    });
  }
}
