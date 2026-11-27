// SPDX-License-Identifier: GPL-3.0-or-later

/// Sink for non-fatal and fatal errors.
///
/// Implementations must only be active after explicit opt-in (SET-03) and
/// must pass every payload through `Redactor` first.
abstract interface class CrashReporter {
  /// Enables or disables reporting. Disabled reporters make no requests.
  Future<void> setEnabled({required bool enabled});

  /// Records [error]. Must be a no-op while disabled.
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  });
}

/// Does nothing. The default in the foss app.
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async {}
}
