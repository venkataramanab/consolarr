// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// foss entry point: no telemetry, no work before the first frame.
void main() {
  runApp(const ProviderScope(child: ConsolarrApp()));
}
