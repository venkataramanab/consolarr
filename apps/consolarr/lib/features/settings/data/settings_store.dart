// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/database/app_database.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, StringExpressionOperators;
import 'package:observability/observability.dart';

/// Reads and writes the small key/value settings (no secrets).
abstract interface class SettingsStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);

  /// Writes all entries atomically (one transaction).
  Future<void> writeAll(Map<String, String> entries);
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

  @override
  Future<void> writeAll(Map<String, String> entries) =>
      _db.transaction(() async {
        for (final e in entries.entries) {
          await write(e.key, e.value);
        }
      });
}

/// Keeps values in memory; tests and previews.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, String>? initial])
    : values = {...?initial};

  final Map<String, String> values;

  /// How many atomic multi-writes happened (tests).
  int writeAllCalls = 0;

  @override
  Future<Map<String, String>> readAll() async => {...values};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> writeAll(Map<String, String> entries) async {
    writeAllCalls++;
    values.addAll(entries);
  }
}

/// The persistent [ConsentStore]: two flags in the settings store, both off
/// unless explicitly stored as on.
class StoredConsentStore implements ConsentStore {
  /// [rows] returns the (shared) stored settings rows and [store] the store,
  /// both resolved on first use, so creating the consent store never opens the
  /// database (nothing may before the first frame).
  StoredConsentStore({
    required Future<Map<String, String>> Function() rows,
    required SettingsStore Function() store,
  }) : _rows = rows,
       _store = store;

  final Future<Map<String, String>> Function() _rows;
  final SettingsStore Function() _store;

  static const _crash = 'consent.crash_reports';
  static const _analytics = 'consent.analytics';

  @override
  Future<ConsentState> load() async {
    final rows = await _rows();
    return ConsentState(
      crashReports: rows[_crash] == '1',
      analytics: rows[_analytics] == '1',
    );
  }

  /// Both flags in one transaction: they are never half-written.
  @override
  Future<void> save(ConsentState state) => _store().writeAll({
    _crash: state.crashReports ? '1' : '0',
    _analytics: state.analytics ? '1' : '0',
  });
}
