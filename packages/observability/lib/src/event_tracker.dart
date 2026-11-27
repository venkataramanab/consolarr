// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/src/analytics.dart';
import 'package:observability/src/breadcrumbs.dart';
import 'package:observability/src/events/catalog.dart';
import 'package:observability/src/redactor.dart';

/// The single entry point for typed events. Sends them to [Analytics] (a no-op
/// unless the user opted in) and records breadcrumbs for navigation and API
/// error categories.
class EventTracker {
  EventTracker({
    required this.analytics,
    required this.breadcrumbs,
    this.redactor = const Redactor(),
  });

  final Analytics analytics;
  final Breadcrumbs breadcrumbs;
  final Redactor redactor;

  Future<void> track(AppEvent event) {
    switch (event) {
      case ScreenViewedEvent(:final screen):
        breadcrumbs.add(Breadcrumb.navigation(screen));
      case ConnectionTestResultEvent(:final errorCategory, :final serviceKind):
        if (errorCategory != null) {
          breadcrumbs.add(Breadcrumb.apiError(errorCategory, serviceKind));
        }
      default:
        break;
    }
    // Defence in depth: values are closed types already.
    final safe = redactor.redactValue(event.parameters)! as Map;
    return analytics.logEvent(
      event.name,
      parameters: {for (final e in safe.entries) e.key as String: e.value!},
    );
  }
}
