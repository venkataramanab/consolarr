// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:observability/src/analytics.dart';
import 'package:observability/src/breadcrumbs.dart';
import 'package:observability/src/consent_store.dart';
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

  @override
  Future<void> setEnabled({required bool enabled}) =>
      inner.setEnabled(enabled: enabled && _isAllowed());

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
/// is given.
class ConsentGatedCrashReporter implements CrashReporter {
  ConsentGatedCrashReporter(this.inner, this._isAllowed);

  final CrashReporter inner;
  final bool Function() _isAllowed;

  @override
  Future<void> setEnabled({required bool enabled}) =>
      inner.setEnabled(enabled: enabled && _isAllowed());

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
  }) async {
    if (!_isAllowed()) return;
    await inner.recordError(error, stackTrace, fatal: fatal);
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
  }) : _rawAnalytics = analytics,
       _rawCrash = crashReporter {
    this.analytics = ConsentGatedAnalytics(analytics, () => _state.analytics);
    this.crashReporter = ConsentGatedCrashReporter(
      crashReporter,
      () => _state.crashReports,
    );
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
    // Gate first: from this line on, nothing is forwarded for a purpose that
    // was withdrawn, whatever the sinks do next.
    _state = next;
    if (previous.crashReports && !next.crashReports) breadcrumbs.clear();
    await _rawAnalytics.setEnabled(enabled: next.analytics);
    await _rawCrash.setEnabled(enabled: next.crashReports);
    if (persist && previous != next) await store.save(next);
    if (previous != next) {
      for (final l in List.of(_listeners)) {
        l();
      }
    }
  }
}
