// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

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

ProviderContainer _container({
  required LibraryData data,
  MemorySonarrPrefsStore? prefs,
  LibraryRunner? runner,
}) {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...sonarrTestOverrides(ScriptedSonarrApi(), prefs: prefs),
      seriesLibraryProvider.overrideWith(() => FakeLibraryNotifier(data)),
      if (runner != null) libraryRunnerProvider.overrideWithValue(runner),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  await c.read(sonarrSessionProvider.future);
  await c.read(seriesLibraryProvider.future);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('saved defaults', () {
    test(
      'sort and filter saved as default come back on the next start',
      () async {
        final prefs = MemorySonarrPrefsStore();
        final first = _container(
          data: dataState(fakeSeriesList(3)),
          prefs: prefs,
        );
        first.listen(libraryQueryProvider, (_, _) {});
        await _settle(first);
        final notifier = first.read(libraryQueryProvider.notifier);
        await notifier.applySort(
          SeriesSortKey.rating,
          ascending: false,
          saveAsDefault: true,
        );
        await notifier.applyFilter(
          const LibraryFilter(
            monitored: MonitoredFilter.monitored,
            tagIds: {7},
          ),
          saveAsDefault: true,
        );

        final second = _container(
          data: dataState(fakeSeriesList(3)),
          prefs: prefs,
        );
        second.listen(libraryQueryProvider, (_, _) {});
        await _settle(second);
        await Future<void>.delayed(Duration.zero);
        final q = second.read(libraryQueryProvider);
        expect(q.sortKey, SeriesSortKey.rating);
        expect(q.ascending, isFalse);
        expect(q.filter.tagIds, {7});
        expect(q.filter.monitored, MonitoredFilter.monitored);
      },
    );

    test('a choice that is not saved is not remembered', () async {
      final prefs = MemorySonarrPrefsStore();
      final first = _container(
        data: dataState(fakeSeriesList(2)),
        prefs: prefs,
      );
      first.listen(libraryQueryProvider, (_, _) {});
      await _settle(first);
      await first
          .read(libraryQueryProvider.notifier)
          .applySort(SeriesSortKey.year, ascending: false);
      expect(prefs.values, isEmpty);
    });

    test('damaged saved values fall back to the built-in defaults', () async {
      final prefs = MemorySonarrPrefsStore()
        ..values['sonarr.srv1.library.sort'] = '{{'
        ..values['sonarr.srv1.library.filter'] = 'nope';
      final c = _container(data: dataState(fakeSeriesList(2)), prefs: prefs);
      c.listen(libraryQueryProvider, (_, _) {});
      await _settle(c);
      expect(c.read(libraryQueryProvider), const LibraryQuery());
    });
  });

  group('visible series', () {
    test('small lists are filtered synchronously', () async {
      final c = _container(data: dataState(fakeSeriesList(5)));
      c.listen(visibleSeriesProvider, (_, _) {});
      await _settle(c);
      c.read(libraryQueryProvider.notifier).setSearch('show 3');
      final v = c.read(visibleSeriesProvider);
      expect(v.count, 1);
      expect(v.computing, isFalse);
    });

    test(
      '10,000 items are computed off the UI isolate and the result lands',
      () async {
        final c = _container(data: dataState(fakeSeriesList(10000)));
        final done = Completer<VisibleSeries>();
        c.listen(visibleSeriesProvider, (_, next) {
          if (!next.computing && next.count > 0 && !done.isCompleted) {
            done.complete(next);
          }
        }, fireImmediately: true);
        await _settle(c);
        final v = await done.future.timeout(const Duration(seconds: 20));
        expect(v.count, 10000);
        expect(v.groups, isNotEmpty);
      },
    );

    test('a stale computation never overwrites a newer query', () async {
      final gates = <Completer<void>>[];
      Future<T> slow<T>(T Function() run) async {
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        return run();
      }

      final c = _container(data: dataState(fakeSeriesList(2000)), runner: slow);
      c.listen(visibleSeriesProvider, (_, _) {}, fireImmediately: true);
      await _settle(c);
      final notifier = c.read(libraryQueryProvider.notifier);
      notifier.setSearch('show 1');
      await Future<void>.delayed(Duration.zero);
      notifier.setSearch('show 2000');
      await Future<void>.delayed(Duration.zero);
      expect(gates.length, greaterThanOrEqualTo(2));
      // The newest finishes first, the older one afterwards.
      gates.last.complete();
      await Future<void>.delayed(Duration.zero);
      for (final g in gates.take(gates.length - 1)) {
        g.complete();
      }
      await Future<void>.delayed(Duration.zero);
      expect(c.read(visibleSeriesProvider).count, 1);
    });

    test('while the library loads there is nothing to show', () {
      final c = ProviderContainer(
        overrides: [
          ...sonarrTestOverrides(ScriptedSonarrApi()),
          seriesLibraryProvider.overrideWith(() => FakeLibraryNotifier(null)),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(visibleSeriesProvider).count, 0);
    });
  });
}
