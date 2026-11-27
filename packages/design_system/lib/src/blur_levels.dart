// SPDX-License-Identifier: GPL-3.0-or-later

/// Gaussian blur sigmas for frosted bars that float over scrolling content.
///
/// Every consumer must fall back to a solid surface when the user chooses
/// reduced transparency or the device cannot blur cheaply.
abstract final class ConsolarrBlur {
  /// No blur: the solid fallback.
  static const double none = 0;
  static const double low = 8;
  static const double medium = 16;
  static const double high = 28;

  /// Tint opacity laid over blurred content so text stays legible.
  static const double barTintOpacity = 0.82;
}
