// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Visual effects switches every blurring or animating component reads.
///
/// Defaults come from the platform (`disableAnimations`, `highContrast`);
/// [ConsolarrEffectsScope] adds in-app overrides (reduce motion, reduce
/// transparency, low-end device).
@immutable
class ConsolarrEffects {
  const ConsolarrEffects({required this.useGlass, required this.animate});

  /// Frosted glass allowed; otherwise bars use a solid surface.
  final bool useGlass;

  /// Looping or decorative motion allowed.
  final bool animate;

  /// Effects for [context], derived from MediaQuery when no scope exists.
  static ConsolarrEffects of(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<_EffectsInherited>();
    if (scoped != null) return scoped.effects;
    return _fromMediaQuery(context);
  }

  static ConsolarrEffects _fromMediaQuery(
    BuildContext context, {
    bool reduceMotion = false,
    bool reduceTransparency = false,
    bool lowEnd = false,
  }) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return ConsolarrEffects(
      useGlass: !(highContrast || reduceTransparency || lowEnd),
      animate: !(disableAnimations || reduceMotion),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConsolarrEffects &&
      other.useGlass == useGlass &&
      other.animate == animate;

  @override
  int get hashCode => Object.hash(useGlass, animate);
}

class _EffectsInherited extends InheritedWidget {
  const _EffectsInherited({required this.effects, required super.child});

  final ConsolarrEffects effects;

  @override
  bool updateShouldNotify(_EffectsInherited old) => old.effects != effects;
}

/// Applies in-app effect overrides below it.
class ConsolarrEffectsScope extends StatelessWidget {
  const ConsolarrEffectsScope({
    required this.child,
    this.reduceMotion = false,
    this.reduceTransparency = false,
    this.lowEnd = false,
    super.key,
  });

  /// In-app "reduce motion" override (on top of the system setting).
  final bool reduceMotion;

  /// In-app "reduce transparency" override.
  final bool reduceTransparency;

  /// Low-end device: no blur.
  final bool lowEnd;

  final Widget child;

  @override
  Widget build(BuildContext context) => _EffectsInherited(
    effects: ConsolarrEffects._fromMediaQuery(
      context,
      reduceMotion: reduceMotion,
      reduceTransparency: reduceTransparency,
      lowEnd: lowEnd,
    ),
    child: child,
  );
}
