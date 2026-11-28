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

  /// Tint opacity of a glass sheet. Higher than a bar's because a sheet holds
  /// body text: at 0.96 every text and status colour keeps WCAG AA (4.5:1)
  /// over a pure black or pure white backdrop, in both themes
  /// (`glass_sheet_contrast_test`). At 0.82 the dark theme's tertiary text
  /// fell to about 3:1 over a bright backdrop.
  static const double sheetTintOpacity = 0.96;
}
