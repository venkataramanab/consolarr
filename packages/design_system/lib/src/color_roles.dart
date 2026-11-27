// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Brightness;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Named colour roles.
///
/// Depth comes from a ladder of neighbouring tonal surfaces (never pure
/// black, never neutral grey) rather than shadows. Text has three tiers and
/// every tier meets WCAG AA (4.5:1) on every surface. Status colours always
/// travel with a text or icon twin; colour is never the only signal.
@immutable
class ConsolarrColorRoles {
  const ConsolarrColorRoles({
    required this.brightness,
    required this.chrome,
    required this.page,
    required this.card,
    required this.raised,
    required this.track,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.error,
  });

  /// Charcoal tonal surfaces on one blue-slate hue, one teal accent.
  static const dark = ConsolarrColorRoles(
    brightness: Brightness.dark,
    chrome: Color(0xFF14171C),
    page: Color(0xFF181B21),
    card: Color(0xFF1F232A),
    raised: Color(0xFF272C34),
    track: Color(0xFF303640),
    textPrimary: Color(0xFFECEFF4),
    textSecondary: Color(0xFFB9C0CC),
    textTertiary: Color(0xFF97A0AF),
    accent: Color(0xFF5CC8D7),
    onAccent: Color(0xFF08191D),
    success: Color(0xFF7BD99A),
    warning: Color(0xFFF0C369),
    error: Color(0xFFFF8F8F),
  );

  /// The same tonal ladder, inverted.
  static const light = ConsolarrColorRoles(
    brightness: Brightness.light,
    chrome: Color(0xFFE6EAF0),
    page: Color(0xFFF2F4F8),
    card: Color(0xFFFBFCFD),
    raised: Color(0xFFFFFFFF),
    track: Color(0xFFDCE1E9),
    textPrimary: Color(0xFF12161D),
    textSecondary: Color(0xFF3F4856),
    textTertiary: Color(0xFF566070),
    accent: Color(0xFF0A6A7D),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF1B6B3A),
    warning: Color(0xFF8A5A00),
    error: Color(0xFFB3261E),
  );

  final Brightness brightness;

  // Surface ladder, outermost to innermost.
  /// Navigation chrome (floating bars).
  final Color chrome;

  /// Page background.
  final Color page;

  /// Cards.
  final Color card;

  /// Raised cards and chips.
  final Color raised;

  /// Progress track.
  final Color track;

  // Text tiers.
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Accent and status.
  final Color accent;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color error;

  /// All surfaces, outermost to innermost.
  List<Color> get surfaces => [chrome, page, card, raised, track];

  /// All text tiers, strongest first.
  List<Color> get textTiers => [textPrimary, textSecondary, textTertiary];

  /// Soft status colours.
  List<Color> get statusColors => [success, warning, error];
}
