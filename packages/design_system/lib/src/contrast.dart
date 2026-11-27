// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio between two opaque colours (1.0 to 21.0).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA minimum for normal-size text.
const double wcagAaNormalText = 4.5;
