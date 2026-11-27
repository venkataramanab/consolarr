// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Play Store entry point.
///
/// This is the only place telemetry SDKs may ever be added. They plug in by
/// overriding `rawCrashReporterProvider` and `rawAnalyticsProvider` (the sinks
/// behind the consent gate). `crashReporterProvider`, `analyticsProvider` and
/// `consentStoreProvider` stay app-owned and must not be overridden here: that
/// would bypass consent (a test enforces it). None are added yet, so behaviour
/// is identical to the foss app.
void main() {
  runApp(const ProviderScope(overrides: [], child: ConsolarrApp()));
}
