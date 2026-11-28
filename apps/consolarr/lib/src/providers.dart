// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/storage/flutter_secure_secret_store.dart';
import 'package:consolarr/src/storage/pinned_markers.dart';
import 'package:consolarr/src/storage/secure_storage_reset.dart';
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
/// table. Read lazily, never before the first frame. It shares the one read of
/// the settings rows with the settings themselves.
final consentStoreProvider = Provider<ConsentStore>(
  (ref) => StoredConsentStore(
    rows: () => ref.read(storedRowsProvider.future),
    store: () => ref.read(settingsStoreProvider),
  ),
);

/// Owns the consent state and the gated sinks below. Right after the first
/// frame it loads the stored choice, so consent applies from startup and not
/// only once the Settings tab has been opened.
final consentManagerProvider = Provider<ConsentManager>((ref) {
  final manager = ConsentManager(
    store: ref.watch(consentStoreProvider),
    analytics: ref.watch(rawAnalyticsProvider),
    crashReporter: ref.watch(rawCrashReporterProvider),
    breadcrumbs: ref.watch(breadcrumbsProvider),
  );
  // An unreadable store leaves every consent off, which is the safe state.
  void load() => unawaited(manager.load().catchError((Object _) {}));
  if (ref.read(firstFrameDoneProvider)) {
    Future.microtask(load);
  } else {
    ref.listen<bool>(firstFrameDoneProvider, (_, done) {
      if (done) load();
    });
  }
  return manager;
});

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

/// Monotonic time since an arbitrary start: unaffected by the user changing
/// the wall clock. The app lock measures the time away with it (together
/// with the wall clock, so a longer absence on either clock locks).
final monotonicClockProvider = Provider<Duration Function()>((ref) {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
});

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
  (ref) => MarkedPinStore(
    SecretBackedPinStore(ref.watch(secretStoreProvider)),
    ref.watch(pinnedMarkersProvider),
  ),
);

/// Non-secret "this key was pinned" markers (drift). A marker without a pin in
/// the secret store reads as a pin mismatch, never as first use.
final pinnedMarkersProvider = Provider<PinnedMarkers>(
  (ref) => DriftPinnedMarkers(ref.watch(databaseProvider)),
);

/// The user-confirmed "Reset secure storage" action.
final secureStorageResetProvider = Provider<SecureStorageReset>(
  (ref) => SecureStorageReset(
    secrets: ref.watch(secretStoreProvider),
    markers: ref.watch(pinnedMarkersProvider),
    db: ref.watch(databaseProvider),
  ),
);

/// Whether the secret store can be read. Probes one fixed, non-secret key, so
/// the error state can offer the reset. `false` only for a Keystore error
/// (a missing value is fine). Lazy: read only after the first frame.
final secretStoreReadableProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  try {
    await ref.watch(secretStoreProvider).read('probe/readable');
    return true;
  } on SecretStoreUnavailable {
    return false;
  }
});

/// Builds every HTTP client (API and images) so one trust policy applies.
final secureHttpClientFactoryProvider = Provider<SecureHttpClientFactory>(
  (ref) => DefaultSecureHttpClientFactory(pins: ref.watch(pinStoreProvider)),
);

/// Window secure flag (reference counted by owner): set while secrets are
/// visible, while the app lock is on and while screenshots are blocked.
final secureScreenProvider = Provider<SecureScreen>(
  (ref) => PlatformSecureScreen(),
);
