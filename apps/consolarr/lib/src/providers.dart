// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/storage/flutter_secure_secret_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

/// The raw crash reporter. No-op in the foss app; the Play entry point may
/// override it. Never read it directly: [crashReporterProvider] is the
/// consent-gated one.
final rawCrashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoopCrashReporter(),
);

/// The raw analytics sink. No-op in the foss app; the Play entry point may
/// override it. Never read it directly: [analyticsProvider] is consent-gated.
final rawAnalyticsProvider = Provider<Analytics>(
  (ref) => const NoopAnalytics(),
);

/// Breadcrumb trail (navigation and API error categories), shared by the
/// tracker and any crash reporter the Play entry point wires in.
final breadcrumbsProvider = Provider<Breadcrumbs>((ref) => Breadcrumbs());

/// Consent seam (SET-03): everything off by default, kept in the settings
/// table. Read lazily, never before the first frame.
final consentStoreProvider = Provider<ConsentStore>(
  (ref) => StoredConsentStore(() => ref.read(settingsStoreProvider)),
);

/// Owns the consent state and the gated sinks below.
final consentManagerProvider = Provider<ConsentManager>(
  (ref) => ConsentManager(
    store: ref.watch(consentStoreProvider),
    analytics: ref.watch(rawAnalyticsProvider),
    crashReporter: ref.watch(rawCrashReporterProvider),
    breadcrumbs: ref.watch(breadcrumbsProvider),
  ),
);

/// Crash reporting seam: forwards only while the user has opted in.
final crashReporterProvider = Provider<CrashReporter>(
  (ref) => ref.watch(consentManagerProvider).crashReporter,
);

/// Analytics seam: forwards only while the user has opted in.
final analyticsProvider = Provider<Analytics>(
  (ref) => ref.watch(consentManagerProvider).analytics,
);

/// The single entry point for typed analytics events. Closed-set parameters
/// only; sends nothing unless the (opt-in) analytics seam is replaced.
final eventTrackerProvider = Provider<EventTracker>(
  (ref) => EventTracker(
    analytics: ref.watch(analyticsProvider),
    breadcrumbs: ref.watch(breadcrumbsProvider),
  ),
);

/// The redacting logger. Messages must carry counts and categories only. It
/// also feeds the opt-in in-app log (SET-04) while that is on.
final loggerProvider = Provider<AppLogger>(
  (ref) => AppLogger(diagnostics: ref.watch(diagnosticsLogProvider)),
);

/// Theme: dark by default, light, or follow the system (SET-07).
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider.select((s) => s.themeMode)),
);

// --- Infrastructure seams ---------------------------------------------------
// All lazy: nothing below is read before the first frame. Tests and the Play
// entry point override these.

/// Current time. Override in tests for stable ages and expiry.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The app database. Opens its file on the first query, not on creation.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.onDisk();
  ref.onDispose(db.close);
  return db;
});

/// Last good API payloads for the offline view.
final payloadCacheProvider = Provider<PayloadCache>(
  (ref) => DriftPayloadCache(ref.watch(databaseProvider)),
);

/// OS-protected secret storage (SRV-09).
final secretStoreProvider = Provider<SecretStore>(
  (ref) => FlutterSecureSecretStore(),
);

/// Trust-on-first-use certificate pins (SRV-06), kept in the secret store.
final pinStoreProvider = Provider<PinStore>(
  (ref) => SecretBackedPinStore(ref.watch(secretStoreProvider)),
);

/// Builds every HTTP client (API and images) so one trust policy applies.
final secureHttpClientFactoryProvider = Provider<SecureHttpClientFactory>(
  (ref) => DefaultSecureHttpClientFactory(pins: ref.watch(pinStoreProvider)),
);

/// Window secure flag, set while secrets are visible.
final secureScreenProvider = Provider<SecureScreen>(
  (ref) => const PlatformSecureScreen(),
);
