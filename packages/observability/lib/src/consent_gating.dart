// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/src/analytics.dart';
import 'package:observability/src/breadcrumbs.dart';
import 'package:observability/src/consent_store.dart';
import 'package:observability/src/crash_payload.dart';
import 'package:observability/src/crash_reporter.dart';
import 'package:observability/src/events/catalog.dart';

/// What the user can consent to separately (SET-03).
enum ConsentPurpose {
  crashReports,
  analytics;

  /// The closed-set parameter for the `consent_changed` event.
  ConsentPurposeParam get param => switch (this) {
    ConsentPurpose.crashReports => ConsentPurposeParam.crashReports,
    ConsentPurpose.analytics => ConsentPurposeParam.analytics,
  };
}

/// An [Analytics] that forwards to [inner] only while analytics consent is
/// given. With consent off the inner sink sees **no call at all**.
class ConsentGatedAnalytics implements Analytics {
  ConsentGatedAnalytics(this.inner, this._isAllowed);

  final Analytics inner;
  final bool Function() _isAllowed;

  /// Enabling is forwarded only while consent is on. Disabling is never
  /// forwarded from here: the owning [ConsentManager] tells the sink once, on
  /// the real on-to-off transition, so a sink whose consent was never given
  /// sees no call at all.
  @override
  Future<void> setEnabled({required bool enabled}) async {
    if (!enabled || !_isAllowed()) return;
    await inner.setEnabled(enabled: true);
  }

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async {
    if (!_isAllowed()) return;
    await inner.logEvent(name, parameters: parameters);
  }
}

/// A [CrashReporter] that forwards to [inner] only while crash-report consent
/// is given, and then only a [CrashPayload]: the raw error object, its message
/// and its raw stack trace never reach the sink.
class ConsentGatedCrashReporter implements CrashReporter {
  ConsentGatedCrashReporter(this.inner, this._isAllowed, {this.categorize});

  final CrashReporter inner;
  final bool Function() _isAllowed;

  /// Maps the app's own typed errors to a closed category (optional).
  final ErrorCategoryParam? Function(Object error)? categorize;

  /// Enabling is forwarded only while consent is on. Disabling is never
  /// forwarded from here: the owning [ConsentManager] tells the sink once, on
  /// the real on-to-off transition, so a sink whose consent was never given
  /// sees no call at all.
  @override
  Future<void> setEnabled({required bool enabled}) async {
    if (!enabled || !_isAllowed()) return;
    await inner.setEnabled(enabled: true);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async {
    if (!_isAllowed()) return;
    final payload = CrashPayload.from(
      error,
      stackTrace,
      categorize: categorize,
    );
    await inner.recordError(payload, payload.stackTrace, fatal: fatal);
  }
}

/// Owns the consent state (persisted in a [ConsentStore]) and the gated
/// sinks. Everything starts off; withdrawing consent stops collection at
/// once, tells the sink to disable itself and drops the queued breadcrumb
/// trail (the crash report's context).
class ConsentManager {
  ConsentManager({
    required this.store,
    required Analytics analytics,
    required CrashReporter crashReporter,
    required this.breadcrumbs,
    ErrorCategoryParam? Function(Object error)? categorize,
  }) : _rawAnalytics = analytics,
       _rawCrash = crashReporter {
    this.analytics = ConsentGatedAnalytics(analytics, () => _state.analytics);
    this.crashReporter = ConsentGatedCrashReporter(
      crashReporter,
      () => _state.crashReports,
      categorize: categorize,
    );
    // Breadcrumbs are crash-report context: kept only while that consent is
    // on (and cleared when it is withdrawn, see [_apply]).
    breadcrumbs.recordingAllowed = () => _state.crashReports;
  }

  final ConsentStore store;
  final Breadcrumbs breadcrumbs;
  final Analytics _rawAnalytics;
  final CrashReporter _rawCrash;

  /// Give these to the tracker and to error handling instead of the raw ones.
  late final Analytics analytics;
  late final CrashReporter crashReporter;

  ConsentState _state = ConsentState.none;
  bool _changedByUser = false;
  final List<void Function()> _listeners = [];

  ConsentState get state => _state;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Reads the stored choice (call after the first frame) and applies it.
  Future<void> load() async {
    final loaded = await store.load();
    // A choice made while the store was being read wins over the stored one.
    if (_changedByUser) return;
    await _apply(loaded, persist: false);
  }

  /// Switches one purpose.
  Future<void> set(ConsentPurpose purpose, {required bool enabled}) {
    _changedByUser = true;
    final next = switch (purpose) {
      ConsentPurpose.crashReports => _state.copyWith(crashReports: enabled),
      ConsentPurpose.analytics => _state.copyWith(analytics: enabled),
    };
    return _apply(next, persist: true);
  }

  Future<void> _apply(ConsentState next, {required bool persist}) async {
    final previous = _state;
    if (previous == next) return;
    // Gate first: from this line on, nothing is forwarded for a purpose that
    // was withdrawn, whatever the sinks do next.
    _state = next;
    if (previous.crashReports && !next.crashReports) breadcrumbs.clear();
    try {
      // Only a purpose whose value changed reaches its raw sink, so a sink
      // that never had consent never sees a call. A failure of one sink does
      // not stop the other.
      Object? failure;
      StackTrace? failureTrace;
      Future<void> tell(Future<void> Function() call) async {
        try {
          await call();
        } on Object catch (e, st) {
          failure ??= e;
          failureTrace ??= st;
        }
      }

      if (previous.analytics != next.analytics) {
        await tell(() => _rawAnalytics.setEnabled(enabled: next.analytics));
      }
      if (previous.crashReports != next.crashReports) {
        await tell(() => _rawCrash.setEnabled(enabled: next.crashReports));
      }
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureTrace ?? StackTrace.empty);
      }
    } finally {
      // The choice is stored and announced even when a sink failed.
      try {
        if (persist) await store.save(next);
      } finally {
        for (final l in List.of(_listeners)) {
          l();
        }
      }
    }
  }
}
