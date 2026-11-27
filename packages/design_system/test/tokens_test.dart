// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palettes = {
    'dark': ConsolarrColorRoles.dark,
    'light': ConsolarrColorRoles.light,
  };

  group('WCAG AA contrast', () {
    palettes.forEach((name, c) {
      test('$name: every text tier on every surface >= 4.5', () {
        for (final text in c.textTiers) {
          for (final surface in c.surfaces) {
            expect(
              contrastRatio(text, surface),
              greaterThanOrEqualTo(wcagAaNormalText),
              reason: '$name text $text on $surface',
            );
          }
        }
      });

      test('$name: accent and status colours on every surface >= 4.5', () {
        for (final fg in [c.accent, ...c.statusColors]) {
          for (final surface in c.surfaces) {
            expect(
              contrastRatio(fg, surface),
              greaterThanOrEqualTo(wcagAaNormalText),
              reason: '$name $fg on $surface',
            );
          }
        }
      });

      test('$name: onAccent on accent >= 4.5', () {
        expect(
          contrastRatio(c.onAccent, c.accent),
          greaterThanOrEqualTo(wcagAaNormalText),
        );
      });
    });
  });

  test('dark surfaces form an ascending tonal ladder, never pure black', () {
    final c = ConsolarrColorRoles.dark;
    final lums = c.surfaces.map((s) => s.computeLuminance()).toList();
    expect(lums, orderedEquals([...lums]..sort()));
    for (final s in c.surfaces) {
      expect(s, isNot(const Color(0xFF000000)));
    }
  });

  test('contrastRatio basics', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      contrastRatio(const Color(0xFF777777), const Color(0xFF777777)),
      closeTo(1, 0.001),
    );
  });

  test('type scale uses exactly two weights', () {
    final weights = ConsolarrTypeScale.all.values.map((s) => s.fontWeight);
    expect(weights.toSet(), {FontWeight.w400, FontWeight.w700});
  });

  test('named tokens are ordered and non-empty', () {
    expect(ConsolarrSpacing.xs, lessThan(ConsolarrSpacing.sm));
    expect(ConsolarrSpacing.lg, lessThan(ConsolarrSpacing.xl));
    expect(ConsolarrRadii.sm, lessThan(ConsolarrRadii.md));
    expect(ConsolarrBlur.none, 0);
    expect(ConsolarrBlur.low, lessThan(ConsolarrBlur.high));
    expect(ConsolarrMotion.instant, Duration.zero);
    expect(ConsolarrMotion.fast, lessThan(ConsolarrMotion.standard));
    expect(ConsolarrMotion.standard, lessThan(ConsolarrMotion.emphasized));
  });

  test('themes build from tokens', () {
    expect(ConsolarrTheme.dark().colorScheme.brightness, Brightness.dark);
    expect(ConsolarrTheme.light().colorScheme.brightness, Brightness.light);
    expect(
      ConsolarrTheme.dark().scaffoldBackgroundColor,
      ConsolarrColorRoles.dark.page,
    );
  });
}
