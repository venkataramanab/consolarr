// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  const palettes = {
    'dark': ConsolarrColorRoles.dark,
    'light': ConsolarrColorRoles.light,
    'dark high contrast': ConsolarrColorRoles.darkHighContrast,
    'light high contrast': ConsolarrColorRoles.lightHighContrast,
  };

  // T5: the body text of a row (secondary tier) and the title (primary) must
  // keep 4.5:1 over the fill at the top of the pulse (1.0), not only at rest.
  for (final entry in palettes.entries) {
    final roles = entry.value;
    for (final state in ProgressRowState.values) {
      for (final pulse in [0.0, 0.5, 1.0]) {
        test('${entry.key} $state pulse $pulse', () {
          final fill = _over(
            progressFillColor(roles, state, pulse),
            roles.card,
          );
          expect(
            _ratio(roles.textSecondary, fill),
            greaterThanOrEqualTo(4.5),
            reason: 'body text',
          );
          expect(
            _ratio(roles.textPrimary, fill),
            greaterThanOrEqualTo(4.5),
            reason: 'title',
          );
        });
      }
    }
  }

  test('the pulse still reads as a pulse (peak is stronger than rest)', () {
    const roles = ConsolarrColorRoles.dark;
    final rest = progressFillColor(roles, ProgressRowState.active, 0);
    final peak = progressFillColor(roles, ProgressRowState.active, 1);
    expect(peak.a, greaterThan(rest.a));
  });
}
