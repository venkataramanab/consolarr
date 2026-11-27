// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Minimum interactive size (SET-12): the standard Android 48dp target, or
/// the larger option for people who need bigger targets.
///
/// Every component reads the current value with [TouchTargets.of]; the app
/// provides the user's choice with [TouchTargetsScope].
@immutable
class TouchTargets {
  const TouchTargets._(this.minimum);

  /// The standard 48dp target.
  static const TouchTargets standard = TouchTargets._(48);

  /// The larger option.
  static const TouchTargets large = TouchTargets._(56);

  /// Minimum width and height of an interactive element, in logical pixels.
  final double minimum;

  /// A square [Size] of [minimum].
  Size get size => Size.square(minimum);

  /// The target size in effect below [context] ([standard] without a scope).
  static TouchTargets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TouchTargetsInherited>()
          ?.targets ??
      standard;

  @override
  bool operator ==(Object other) =>
      other is TouchTargets && other.minimum == minimum;

  @override
  int get hashCode => minimum.hashCode;
}

/// An [InheritedTheme] so that sheets and dialogs opened from below a scope
/// keep the user's target size.
class _TouchTargetsInherited extends InheritedTheme {
  const _TouchTargetsInherited({required this.targets, required super.child});

  final TouchTargets targets;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _TouchTargetsInherited(targets: targets, child: child);

  @override
  bool updateShouldNotify(_TouchTargetsInherited old) => old.targets != targets;
}

/// Provides the user's touch-target choice to every component below it.
///
/// ```dart
/// TouchTargetsScope(
///   targets: largerTargets ? TouchTargets.large : TouchTargets.standard,
///   child: const MyScreen(),
/// )
/// ```
class TouchTargetsScope extends StatelessWidget {
  const TouchTargetsScope({
    required this.targets,
    required this.child,
    super.key,
  });

  final TouchTargets targets;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _TouchTargetsInherited(targets: targets, child: child);
}
