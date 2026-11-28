// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Text colours that appear on a sheet: the three text tiers, the accent
/// (links, chips) and the status colours.
List<(String, Color)> _texts(ConsolarrColorRoles r) => [
  ('primary', r.textPrimary),
  ('secondary', r.textSecondary),
  ('tertiary', r.textTertiary),
  ('accent', r.accent),
  ('success', r.success),
  ('warning', r.warning),
  ('error', r.error),
];

/// The backdrops behind a glass sheet. Blur averages what is behind it, so
/// the worst case for any text colour is a uniform black or white backdrop.
const _backdrops = {'black': Color(0xFF000000), 'white': Color(0xFFFFFFFF)};

void main() {
  const palettes = {
    'dark': ConsolarrColorRoles.dark,
    'light': ConsolarrColorRoles.light,
    'dark high contrast': ConsolarrColorRoles.darkHighContrast,
    'light high contrast': ConsolarrColorRoles.lightHighContrast,
  };

  for (final entry in palettes.entries) {
    final roles = entry.value;

    test('${entry.key}: text on the solid fallback surface is AA', () {
      for (final (name, color) in _texts(roles)) {
        expect(
          contrastRatio(color, roles.raised),
          greaterThanOrEqualTo(wcagAaNormalText),
          reason: '$name on the solid sheet',
        );
      }
    });

    for (final backdrop in _backdrops.entries) {
      test('${entry.key}: text on the glass sheet over a ${backdrop.key} '
          'backdrop is AA', () {
        final surface = Color.alphaBlend(glassSheetTint(roles), backdrop.value);
        for (final (name, color) in _texts(roles)) {
          expect(
            contrastRatio(color, surface),
            greaterThanOrEqualTo(wcagAaNormalText),
            reason: '$name on the glass sheet over ${backdrop.key}',
          );
        }
      });
    }
  }
}
