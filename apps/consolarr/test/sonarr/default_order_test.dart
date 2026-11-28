// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/library_providers.dart';
import 'package:consolarr/features/sonarr/application/library_query.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'library_harness.dart';
import 'support.dart';

SonarrSeries _added(int i, String title, DateTime? added) =>
    SonarrSeries.fromJson({
      ...fakeSeries(i, title: title).toJson(),
      'added': added?.toIso8601String(),
    });

ProviderContainer _container(MemorySonarrPrefsStore prefs) {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...sonarrTestOverrides(ScriptedSonarrApi(), prefs: prefs),
      seriesLibraryProvider.overrideWith(
        () => FakeLibraryNotifier(dataState(fakeSeriesList(3))),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<LibraryQuery> _startQuery(ProviderContainer c) async {
  c.listen(libraryQueryProvider, (_, _) {});
  await c.read(sonarrSessionProvider.future);
  await c.read(seriesLibraryProvider.future);
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(libraryQueryProvider);
}

void main() {
  test('the built-in library view is date added, newest first', () {
    const q = LibraryQuery();
    expect(q.sortKey, SeriesSortKey.added);
    expect(q.ascending, isFalse);
  });

  test('newest first; undated last; ties by title', () {
    final all = [
      _added(1, 'Old', DateTime.utc(2024, 1, 1)),
      _added(2, 'Bravo', DateTime.utc(2025, 6, 1)),
      _added(3, 'Alpha', DateTime.utc(2025, 6, 1)),
      _added(4, 'Newest', DateTime.utc(2026, 2, 1)),
      _added(5, 'Undated', null),
    ];
    final rows = applyLibraryQuery(all, const LibraryQuery(), const {});
    expect([for (final s in rows) s.id], [4, 3, 2, 1, 5]);
  });

  test('without a saved default the built-in one applies', () async {
    final q = await _startQuery(_container(MemorySonarrPrefsStore()));
    expect(q.sortKey, SeriesSortKey.added);
    expect(q.ascending, isFalse);
  });

  test('a saved default beats the built-in one', () async {
    final prefs = MemorySonarrPrefsStore();
    final first = _container(prefs);
    await _startQuery(first);
    await first
        .read(libraryQueryProvider.notifier)
        .applySort(SeriesSortKey.title, ascending: true, saveAsDefault: true);

    final q = await _startQuery(_container(prefs));
    expect(q.sortKey, SeriesSortKey.title);
    expect(q.ascending, isTrue);
  });
}
