// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, StringExpressionOperators;
import 'package:observability/observability.dart';

/// Reads and writes the small key/value settings (no secrets).
abstract interface class SettingsStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
}

/// [SettingsStore] on the `AppStateRows` table; touches only `settings.` and
/// `consent.` keys.
class DriftSettingsStore implements SettingsStore {
  DriftSettingsStore(this._db);

  final AppDatabase _db;

  @override
  Future<Map<String, String>> readAll() async {
    final rows = await (_db.select(
      _db.appStateRows,
    )..where((r) => r.key.like('settings.%') | r.key.like('consent.%'))).get();
    return {for (final r in rows) r.key: r.value};
  }

  @override
  Future<void> write(String key, String value) => _db
      .into(_db.appStateRows)
      .insertOnConflictUpdate(
        AppStateRowsCompanion.insert(key: key, value: value),
      );
}

/// Keeps values in memory; tests and previews.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<Map<String, String>> readAll() async => {...values};

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// The persistent [ConsentStore]: two flags in the settings store, both off
/// unless explicitly stored as on.
class StoredConsentStore implements ConsentStore {
  /// [store] is resolved on first use, so creating the consent store never
  /// opens the database (nothing may before the first frame).
  StoredConsentStore(this._store);

  final SettingsStore Function() _store;

  static const _crash = 'consent.crash_reports';
  static const _analytics = 'consent.analytics';

  @override
  Future<ConsentState> load() async {
    final rows = await _store().readAll();
    return ConsentState(
      crashReports: rows[_crash] == '1',
      analytics: rows[_analytics] == '1',
    );
  }

  @override
  Future<void> save(ConsentState state) async {
    await _store().write(_crash, state.crashReports ? '1' : '0');
    await _store().write(_analytics, state.analytics ? '1' : '0');
  }
}
