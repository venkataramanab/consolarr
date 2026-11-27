// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/painting.dart';

/// Corner radii. Rounded cards, pill chips, floating pill bar.
abstract final class ConsolarrRadii {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius bar = BorderRadius.all(Radius.circular(pill));
}
