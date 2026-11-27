// SPDX-License-Identifier: GPL-3.0-or-later

/// The user's separate opt-in choices. Everything defaults to off.
class ConsentState {
  const ConsentState({this.crashReports = false, this.analytics = false});

  /// All consents withheld.
  static const none = ConsentState();

  final bool crashReports;
  final bool analytics;

  ConsentState copyWith({bool? crashReports, bool? analytics}) => ConsentState(
    crashReports: crashReports ?? this.crashReports,
    analytics: analytics ?? this.analytics,
  );

  @override
  bool operator ==(Object other) =>
      other is ConsentState &&
      other.crashReports == crashReports &&
      other.analytics == analytics;

  @override
  int get hashCode => Object.hash(crashReports, analytics);
}

/// Persists [ConsentState]. Loaded lazily, never before the first frame.
abstract interface class ConsentStore {
  Future<ConsentState> load();
  Future<void> save(ConsentState state);
}

/// Always reports no consent and discards writes. The foss default.
class NoopConsentStore implements ConsentStore {
  const NoopConsentStore();

  @override
  Future<ConsentState> load() async => ConsentState.none;

  @override
  Future<void> save(ConsentState state) async {}
}

/// Keeps consent in memory only; for tests and previews.
class InMemoryConsentStore implements ConsentStore {
  InMemoryConsentStore([this._state = ConsentState.none]);

  ConsentState _state;

  @override
  Future<ConsentState> load() async => _state;

  @override
  Future<void> save(ConsentState state) async => _state = state;
}
