// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/painting.dart';

/// One sans family (Inter, OFL) in two weights. Hierarchy comes from weight
/// and tone, not from many sizes. Everything scales with system text size.
abstract final class ConsolarrTypeScale {
  static const String family = 'Inter';
  static const String package = 'design_system';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight bold = FontWeight.w700;

  /// Fixed-width digits for values that change live (speeds, percentages).
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  // Tighter tracking on large display text only.
  static const TextStyle display = TextStyle(
    fontSize: 32,
    height: 1.2,
    fontWeight: bold,
    letterSpacing: -0.6,
  );
  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: bold,
  );
  static const TextStyle heading = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: bold,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: regular,
  );
  static const TextStyle label = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: bold,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: regular,
  );

  /// All named styles, for tests.
  static const Map<String, TextStyle> all = {
    'display': display,
    'title': title,
    'heading': heading,
    'body': body,
    'label': label,
    'caption': caption,
  };
}
