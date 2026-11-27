// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

/// Theme + accessibility switches a component is pumped under.
class A11yVariant {
  const A11yVariant(
    this.name, {
    this.highContrast = false,
    this.largeTargets = false,
    this.reduceMotion = true,
  });

  final String name;
  final bool highContrast;
  final bool largeTargets;
  final bool reduceMotion;

  /// The four theme variants every new component is verified under.
  static const normal = A11yVariant('normal');
  static const highContrastVariant = A11yVariant(
    'high contrast',
    highContrast: true,
  );
  static const large = A11yVariant('large targets', largeTargets: true);
}

/// [child] inside the harness app, themed per [harness] brightness and
/// [a11y] (contrast variant, touch targets, motion).
Widget hostApp(
  HarnessVariant harness,
  Widget child, {
  A11yVariant a11y = A11yVariant.normal,
  bool scroll = true,
  bool reduceTransparency = false,
}) {
  final touch = a11y.largeTargets ? TouchTargets.large : TouchTargets.standard;
  final theme = harness.brightness == Brightness.dark
      ? ConsolarrTheme.dark(
          highContrast: a11y.highContrast,
          touchTargets: touch,
        )
      : ConsolarrTheme.light(
          highContrast: a11y.highContrast,
          touchTargets: touch,
        );
  return harnessApp(
    harness,
    Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamilyFallback: harnessFontFallback,
        ),
      ),
      child: TouchTargetsScope(
        targets: touch,
        child: ConsolarrEffectsScope(
          motion: a11y.reduceMotion
              ? MotionPreference.reduced
              : MotionPreference.system,
          reduceTransparency: reduceTransparency,
          child: Scaffold(
            body: SafeArea(
              child: scroll ? SingleChildScrollView(child: child) : child,
            ),
          ),
        ),
      ),
    ),
  );
}
