// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palettes = {
    'dark': ConsolarrColorRoles.dark,
    'light': ConsolarrColorRoles.light,
    'dark high contrast': ConsolarrColorRoles.darkHighContrast,
    'light high contrast': ConsolarrColorRoles.lightHighContrast,
  };

  group('high contrast variants (WCAG AAA, 7:1)', () {
    for (final name in ['dark high contrast', 'light high contrast']) {
      final c = palettes[name]!;
      test('$name: text tiers incl. tertiary, accent and status roles', () {
        for (final fg in [...c.textTiers, c.accent, ...c.statusColors]) {
          for (final surface in c.surfaces) {
            expect(
              contrastRatio(fg, surface),
              greaterThanOrEqualTo(7),
              reason: '$name $fg on $surface',
            );
          }
        }
        expect(contrastRatio(c.onAccent, c.accent), greaterThanOrEqualTo(7));
      });

      test('$name: is at least as strong as the normal variant', () {
        final normal = ConsolarrColorRoles.forBrightness(c.brightness);
        for (var i = 0; i < 3; i++) {
          expect(
            contrastRatio(c.textTiers[i], c.page),
            greaterThanOrEqualTo(
              contrastRatio(normal.textTiers[i], normal.page),
            ),
          );
        }
        expect(c.isHighContrast, isTrue);
        expect(normal.isHighContrast, isFalse);
      });
    }

    test('dark high-contrast surfaces keep an ascending ladder', () {
      final lums = ConsolarrColorRoles.darkHighContrast.surfaces
          .map((s) => s.computeLuminance())
          .toList();
      expect(lums, orderedEquals([...lums]..sort()));
    });
  });

  test('forBrightness picks all four variants', () {
    expect(
      ConsolarrColorRoles.forBrightness(Brightness.dark),
      ConsolarrColorRoles.dark,
    );
    expect(
      ConsolarrColorRoles.forBrightness(Brightness.light, highContrast: true),
      ConsolarrColorRoles.lightHighContrast,
    );
  });

  test('theme carries the roles variant', () {
    expect(
      ConsolarrTheme.dark(highContrast: true)
          .extension<ConsolarrRolesExtension>()!
          .roles,
      ConsolarrColorRoles.darkHighContrast,
    );
    expect(
      ConsolarrTheme.light().extension<ConsolarrRolesExtension>()!.roles,
      ConsolarrColorRoles.light,
    );
  });

  test('touch targets: standard 48, large larger', () {
    expect(TouchTargets.standard.minimum, 48);
    expect(TouchTargets.large.minimum, greaterThan(48));
    expect(
      ConsolarrTheme.dark(touchTargets: TouchTargets.large)
          .iconButtonTheme
          .style!
          .minimumSize!
          .resolve({}),
      TouchTargets.large.size,
    );
  });

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
