// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// Crash reporting seam. No-op in the foss app; the Play entry point may
/// override it after the user opts in.
final crashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
);

/// Analytics seam. No-op in the foss app.
final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());

/// Consent seam: everything off by default. Read lazily, never before the
/// first frame.
final consentStoreProvider = Provider<ConsentStore>(
  (ref) => const NoopConsentStore(),
);

/// Dark is the default identity; a follow-system setting will override this.
final themeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.dark);
