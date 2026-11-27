// SPDX-License-Identifier: GPL-3.0-or-later

/// The in-app motion setting (SET-12).
///
/// [system] follows the platform's "remove animations" setting; [reduced]
/// additionally turns decorative and looping motion off regardless of the
/// platform. The app can never force motion on over the platform setting.
/// Consumed by `ConsolarrEffectsScope`, which every animating component
/// (skeletons, progress pulse, staged reveal, sheets) reads through
/// `ConsolarrEffects`.
enum MotionPreference {
  /// Follow the system setting.
  system,

  /// Reduce motion even when the system allows it.
  reduced;

  /// Whether this preference asks for reduced motion on its own.
  bool get reducesMotion => this == MotionPreference.reduced;
}
