// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/color_roles.dart';
import 'package:design_system/src/radii.dart';
import 'package:design_system/src/spacing.dart';
import 'package:design_system/src/type_scale.dart';
import 'package:material_ui/material_ui.dart';

/// Builds Material themes from Consolarr tokens.
abstract final class ConsolarrTheme {
  static ThemeData dark() => _build(ConsolarrColorRoles.dark);
  static ThemeData light() => _build(ConsolarrColorRoles.light);

  static ThemeData _build(ConsolarrColorRoles c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.error,
      onError: c.brightness == Brightness.dark ? c.page : c.raised,
      surface: c.page,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.chrome,
      surfaceContainerLow: c.page,
      surfaceContainer: c.card,
      surfaceContainerHigh: c.raised,
      surfaceContainerHighest: c.track,
      outline: c.textTertiary,
      outlineVariant: c.track,
    );

    TextStyle style(TextStyle base, Color color) => base.copyWith(
      color: color,
      fontFamily: ConsolarrTypeScale.family,
      package: ConsolarrTypeScale.package,
    );

    final textTheme = TextTheme(
      displaySmall: style(ConsolarrTypeScale.display, c.textPrimary),
      headlineSmall: style(ConsolarrTypeScale.title, c.textPrimary),
      titleMedium: style(ConsolarrTypeScale.heading, c.textPrimary),
      bodyLarge: style(ConsolarrTypeScale.body, c.textPrimary),
      bodyMedium: style(ConsolarrTypeScale.body, c.textSecondary),
      labelLarge: style(ConsolarrTypeScale.label, c.textPrimary),
      bodySmall: style(ConsolarrTypeScale.caption, c.textTertiary),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.page,
      canvasColor: c.page,
      fontFamily: ConsolarrTypeScale.family,
      package: ConsolarrTypeScale.package,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: c.chrome,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleMedium,
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: ConsolarrRadii.card),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(ConsolarrSpacing.minTapTarget),
          foregroundColor: c.textPrimary,
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
