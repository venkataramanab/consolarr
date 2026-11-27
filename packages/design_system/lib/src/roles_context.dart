// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/color_roles.dart';
import 'package:material_ui/material_ui.dart';

/// Carries the active [ConsolarrColorRoles] inside the [ThemeData], so the
/// high-contrast variant travels with the theme (`ConsolarrTheme.dark(
/// highContrast: true)`).
@immutable
class ConsolarrRolesExtension extends ThemeExtension<ConsolarrRolesExtension> {
  const ConsolarrRolesExtension(this.roles);

  final ConsolarrColorRoles roles;

  @override
  ConsolarrRolesExtension copyWith({ConsolarrColorRoles? roles}) =>
      ConsolarrRolesExtension(roles ?? this.roles);

  @override
  ConsolarrRolesExtension lerp(
    covariant ConsolarrRolesExtension? other,
    double t,
  ) => t < 0.5 || other == null ? this : other;
}

/// Reads the Consolarr colour roles of the current theme (brightness and
/// contrast variant).
extension ConsolarrRolesContext on BuildContext {
  ConsolarrColorRoles get roles {
    final theme = Theme.of(this);
    return theme.extension<ConsolarrRolesExtension>()?.roles ??
        ConsolarrColorRoles.forBrightness(theme.brightness);
  }
}
