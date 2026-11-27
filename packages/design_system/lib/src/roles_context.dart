// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/src/color_roles.dart';
import 'package:material_ui/material_ui.dart';

/// Reads the Consolarr colour roles matching the current theme brightness.
extension ConsolarrRolesContext on BuildContext {
  ConsolarrColorRoles get roles => Theme.of(this).brightness == Brightness.dark
      ? ConsolarrColorRoles.dark
      : ConsolarrColorRoles.light;
}
