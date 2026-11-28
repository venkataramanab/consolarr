// SPDX-License-Identifier: GPL-3.0-or-later

/// Telemetry interfaces, no-op implementations, redaction and logging.
///
/// This package contains no third-party SDKs. Concrete reporters belong in
/// the Play entry point only.
library;

export 'src/analytics.dart';
export 'src/breadcrumbs.dart';
export 'src/consent_gating.dart';
export 'src/consent_store.dart';
export 'src/crash_reporter.dart';
export 'src/diagnostics.dart';
export 'src/event_tracker.dart';
export 'src/events/catalog.dart';
export 'src/redactor.dart';
