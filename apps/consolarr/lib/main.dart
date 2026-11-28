// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// foss entry point: no telemetry, no work before the first frame.
void main() {
  runApp(
    ProviderScope(
      overrides: [appFlavorProvider.overrideWithValue(AppFlavor.foss)],
      child: const ConsolarrApp(),
    ),
  );
}
