// SPDX-License-Identifier: GPL-3.0-or-later

/// Spacing scale (logical pixels). Gutters and section gaps come from here.
abstract final class ConsolarrSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter.
  static const double gutter = lg;

  /// Gap between sections.
  static const double section = xl;

  /// Minimum interactive target (Android guideline: 48dp).
  static const double minTapTarget = 48;
}
