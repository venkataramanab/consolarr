// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/platform/secure_screen.dart';
import 'package:consolarr/src/storage/flutter_secure_secret_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

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
