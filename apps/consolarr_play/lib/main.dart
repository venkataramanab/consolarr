// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Play Store entry point.
///
/// This is the only place telemetry SDKs may ever be added. They plug in by
/// overriding `crashReporterProvider`, `analyticsProvider` and
/// `consentStoreProvider`; none are added yet, so behaviour is identical to
/// the foss app.
void main() {
  runApp(const ProviderScope(overrides: [], child: ConsolarrApp()));
}
