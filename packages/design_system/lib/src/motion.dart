// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/animation.dart';

/// Named motion durations and curves. Motion explains structure and is short
/// and interruptible; reduced motion collapses these to crossfades.
abstract final class ConsolarrMotion {
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasized = Duration(milliseconds: 360);
  static const Duration pulse = Duration(milliseconds: 1400);
  static const Duration shimmer = Duration(milliseconds: 1600);

  static const Curve standardCurve = Curves.easeInOutCubic;
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
}
