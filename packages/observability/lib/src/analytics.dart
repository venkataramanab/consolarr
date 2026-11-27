// SPDX-License-Identifier: GPL-3.0-or-later

/// Sink for anonymous usage events.
///
/// Payloads must never contain URLs, keys or media titles.
abstract interface class Analytics {
  /// Enables or disables collection. Disabled analytics make no requests.
  Future<void> setEnabled({required bool enabled});

  /// Logs an event. Must be a no-op while disabled.
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  });
}

/// Does nothing. The default in the foss app.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async {}
}
