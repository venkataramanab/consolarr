// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';

import 'support.dart';

class _Capture implements Analytics {
  final List<(String, Map<String, Object>)> events = [];
  @override
  Future<void> setEnabled({required bool enabled}) async {}
  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async => events.add((name, parameters));
}

ProviderContainer _container(
  FakeRadarrApi api, {
  MemoryPrefs? prefs,
  MemoryPayloadCache? cache,
  _Capture? capture,
}) {
  final c = ProviderContainer(
    overrides: [
      ...radarrOverrides(api, prefs: prefs, cache: cache),
      if (capture != null) analyticsProvider.overrideWithValue(capture),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('library notifier', () {
    test('loads, then refresh keeps content and marks offline', () async {
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(3)));
      final c = _container(api);
      final first = await c.read(movieLibraryProvider.future);
      expect(first, isA<RadarrData<List<RadarrMovie>>>());
      api.moviesResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
      await c.read(movieLibraryProvider.notifier).refresh();
      final after = c.read(movieLibraryProvider).value!;
      expect(after, isA<RadarrData<List<RadarrMovie>>>());
      expect((after as RadarrData<List<RadarrMovie>>).isOffline, isTrue);
      expect(after.value, hasLength(3));
    });

    test(
      'auth_failed on refresh is shown, never hidden behind old data',
      () async {
        final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(3)));
        final c = _container(api);
        await c.read(movieLibraryProvider.future);
        api.moviesResult = const Result.err(AppError(ErrorCategory.authFailed));
        await c.read(movieLibraryProvider.notifier).refresh();
        expect(
          c.read(movieLibraryProvider).value,
          isA<RadarrFailure<List<RadarrMovie>>>(),
        );
      },
    );

    test('API failures leave an error-category breadcrumb only', () async {
      final api = FakeRadarrApi(
        moviesResult: const Result.err(AppError(ErrorCategory.timeout)),
      );
      final c = _container(api);
      c.read(breadcrumbsProvider).recordingAllowed = () => true;
      await c.read(movieLibraryProvider.future);
      final crumbs = c.read(breadcrumbsProvider).entries.map((e) => e.line);
      expect(crumbs, contains('api_error timeout radarr'));
    });
  });

  group('saved sort and filter defaults (RAD-03/04)', () {
    test('only an explicit save writes, per server', () async {
      final prefs = MemoryPrefs();
      final c = _container(FakeRadarrApi(), prefs: prefs);
      await c.read(radarrContextProvider.future);
      final n = c.read(libraryQueryProvider.notifier);
      await n.setSort(MovieSortKey.size, ascending: false);
      expect(prefs.values, isEmpty);
      await n.setSort(
        MovieSortKey.rating,
        ascending: false,
        saveAsDefault: true,
      );
      expect(prefs.values.keys.single, 'radarr.srv1.library.sort');
      await n.setFilter(
        const MovieFilter(file: FileFilter.missing),
        saveAsDefault: true,
      );
      expect(prefs.values.keys, contains('radarr.srv1.library.filter'));
    });

    test('defaults are restored for the server', () async {
      final prefs = MemoryPrefs()
        ..values['radarr.srv1.library.sort'] = '{"key":"year","asc":false}'
        ..values['radarr.srv1.library.filter'] =
            '{"monitored":"monitored","file":"any"}';
      final c = _container(FakeRadarrApi(), prefs: prefs);
      await c.read(radarrContextProvider.future);
      c.listen(libraryQueryProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final q = c.read(libraryQueryProvider);
      expect(q.sort, MovieSortKey.year);
      expect(q.ascending, isFalse);
      expect(q.filter.monitored, MonitoredFilter.monitored);
    });

    test('garbage in storage falls back to defaults', () async {
      final prefs = MemoryPrefs()
        ..values['radarr.srv1.library.sort'] = 'not json'
        ..values['radarr.srv1.library.filter'] = '[1]';
      final c = _container(FakeRadarrApi(), prefs: prefs);
      await c.read(radarrContextProvider.future);
      c.listen(libraryQueryProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(libraryQueryProvider), const MovieQuery());
    });
  });

  group('automatic search (RAD-12)', () {
    test('polls through queued, running and done, with an event', () async {
      final api = FakeRadarrApi();
      final capture = _Capture();
      final c = _container(api, capture: capture);
      c.listen(searchStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      final phases = <SearchPhase?>[];
      c.listen(
        searchStatusProvider,
        (_, next) => phases.add(next[('srv1', 7)]),
      );
      await c.read(searchStatusProvider.notifier).searchMovie(7);
      expect(phases, [
        SearchPhase.starting,
        SearchPhase.queued,
        SearchPhase.searching,
        SearchPhase.done,
      ]);
      final e = capture.events.singleWhere(
        (e) => e.$1 == 'radarr_search_started',
      );
      expect(e.$2, {'kind': 'movie'});
    });

    test('a command that never finishes stops after the poll bound', () async {
      final api = FakeRadarrApi()..commandScript = [ArrCommandStatus.started];
      final c = _container(api);
      c.listen(searchStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      await c.read(searchStatusProvider.notifier).searchMovie(7);
      expect(api.commandCalls, maxCommandPolls);
      // Not a failure: the server may still be searching.
      expect(
        c.read(searchStatusProvider)[('srv1', 7)],
        SearchPhase.stillRunning,
      );
    });

    test(
      'R-L5: leaving the screen (last listener gone) ends the polling',
      () async {
        final api = FakeRadarrApi()..commandScript = [ArrCommandStatus.started];
        final c = _container(api);
        final sub = c.listen(searchStatusProvider, (_, _) {});
        await c.read(radarrContextProvider.future);
        final running = c.read(searchStatusProvider.notifier).searchMovie(7);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        sub.close();
        await running;
        // Far below the bound: the loop stopped when the provider was disposed.
        expect(api.commandCalls, lessThan(maxCommandPolls));
        final settled = api.commandCalls;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(api.commandCalls, settled);
      },
    );

    test(
      'a failed start is failed, and a second tap while busy is ignored',
      () async {
        final api = FakeRadarrApi()
          ..commandStart = const Result.err(
            AppError(ErrorCategory.serverError),
          );
        final c = _container(api);
        c.listen(searchStatusProvider, (_, _) {});
        await c.read(radarrContextProvider.future);
        await c.read(radarrContextProvider.future);
        await c.read(searchStatusProvider.notifier).searchMovie(7);
        expect(c.read(searchStatusProvider)[('srv1', 7)], SearchPhase.failed);
        expect(api.calls, ['search [7]']);

        final slow = FakeRadarrApi();
        final c2 = _container(slow);
        c2.listen(searchStatusProvider, (_, _) {});
        await c2.read(radarrContextProvider.future);
        await c2.read(radarrContextProvider.future);
        final n = c2.read(searchStatusProvider.notifier);
        final a = n.searchMovie(7);
        final b = n.searchMovie(7);
        await Future.wait([a, b]);
        expect(slow.calls, ['search [7]']);
      },
    );

    test('search all missing uses its own key', () async {
      final api = FakeRadarrApi();
      final capture = _Capture();
      final c = _container(api, capture: capture);
      c.listen(searchStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      await c.read(searchStatusProvider.notifier).searchAllMissing();
      expect(
        c.read(searchStatusProvider)[(
          'srv1',
          SearchStatusNotifier.allMissingKey,
        )],
        SearchPhase.done,
      );
      expect(
        capture.events.singleWhere((e) => e.$1 == 'radarr_search_started').$2,
        {'kind': 'all_missing'},
      );
    });
  });

  group('events carry enums and bools only', () {
    test('removal, grab, add and search events contain no free text', () async {
      final api = FakeRadarrApi()
        ..queueResult = Result.ok([
          fakeQueueItem(1, title: 'Secret.Release.Name', size: 10),
        ])
        ..releasesResult = const Result.ok([]);
      final capture = _Capture();
      final c = _container(api, capture: capture);
      c.listen(queueProvider, (_, _) {});
      c.listen(grabStatusProvider, (_, _) {});
      await c.read(queueProvider.future);
      await c
          .read(queueProvider.notifier)
          .remove(
            fakeQueueItem(1, title: 'Secret.Release.Name'),
            removeFromClient: true,
            blocklist: ArrBlocklistChoice.blocklistOnly,
          );
      await c
          .read(grabStatusProvider.notifier)
          .grab(
            fakeRelease(
              'secret-guid',
              indexerId: 3,
              title: 'Secret.Release.Name',
              approved: false,
              rejections: const ['why'],
            ),
          );
      for (final (name, params) in capture.events) {
        for (final v in params.values) {
          expect(v is bool || v is int || v is String, isTrue, reason: name);
          expect('$v', isNot(contains('Secret')));
          expect('$v', isNot(contains('secret-guid')));
          expect('$v', isNot(contains('radarr.example')));
        }
      }
      expect(
        capture.events.map((e) => e.$1),
        containsAll(['radarr_queue_item_removed', 'radarr_release_grabbed']),
      );
      expect(
        capture.events
            .singleWhere((e) => e.$1 == 'radarr_queue_item_removed')
            .$2,
        {'removal': 'blocklist_only'},
      );
      expect(
        capture.events.singleWhere((e) => e.$1 == 'radarr_release_grabbed').$2,
        {'was_rejected': true},
      );
    });

    test('no breadcrumb or log carries a title', () async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([fakeMovie(1, title: 'Secret Title')]),
      );
      final c = _container(api);
      c.read(breadcrumbsProvider).recordingAllowed = () => true;
      await c.read(movieLibraryProvider.future);
      api.moviesResult = const Result.err(AppError(ErrorCategory.serverError));
      await c.read(movieLibraryProvider.notifier).refresh();
      final crumbs = c.read(breadcrumbsProvider).entries;
      expect(crumbs, isNotEmpty);
      for (final b in crumbs) {
        expect(b.line, isNot(contains('Secret')));
      }
    });
  });

  group('queue notifier', () {
    test('removal drops the row; a failed removal keeps it', () async {
      final api = FakeRadarrApi()
        ..queueResult = Result.ok([
          fakeQueueItem(1, size: 1),
          fakeQueueItem(2, size: 1),
        ]);
      final c = _container(api);
      c.listen(queueProvider, (_, _) {});
      await c.read(queueProvider.future);
      api.removeResult = const Result.err(AppError(ErrorCategory.timeout));
      final err = await c
          .read(queueProvider.notifier)
          .remove(
            fakeQueueItem(1),
            removeFromClient: false,
            blocklist: ArrBlocklistChoice.none,
          );
      expect(err?.category, ErrorCategory.timeout);
      expect(
        (c.read(queueProvider).value as RadarrData<List<ArrQueueItem>>).value,
        hasLength(2),
      );
      api.removeResult = const Result.ok(null);
      await c
          .read(queueProvider.notifier)
          .remove(
            fakeQueueItem(1),
            removeFromClient: false,
            blocklist: ArrBlocklistChoice.none,
          );
      expect(
        (c.read(queueProvider).value as RadarrData<List<ArrQueueItem>>)
            .value
            .single
            .id,
        2,
      );
    });
  });

  group('lookup', () {
    test('a newer search wins over a slower older one', () async {
      final slow = Completer<Result<List<RadarrMovie>>>();
      final api = _LookupApi(slow);
      final c = _container(api);
      c.listen(movieLookupProvider, (_, _) {});
      final n = c.read(movieLookupProvider.notifier);
      final first = n.search('old');
      await Future<void>.delayed(Duration.zero);
      await n.search('new');
      slow.complete(Result.ok([fakeMovie(1, title: 'Old Result')]));
      await first;
      final state = c.read(movieLookupProvider) as LookupResults;
      expect(state.movies.single.title, 'New Result');
    });
  });

  group('calendar entries', () {
    test('one entry per date and type, sorted, filtered by type', () {
      final m = fakeMovie(
        1,
        inCinemas: DateTime.utc(2026, 5, 2),
        digital: DateTime.utc(2026, 5, 1),
      );
      final all = calendarEntries([m], {...ReleaseType.values});
      expect(
        [for (final e in all) e.type],
        [ReleaseType.digital, ReleaseType.cinema],
      );
      expect(calendarEntries([m], {ReleaseType.cinema}), hasLength(1));
      expect(calendarEntries([m], {ReleaseType.physical}), isEmpty);
      expect(
        calendarEntries(
          [m],
          {...ReleaseType.values},
          from: DateTime.utc(2026, 5, 2),
        ),
        hasLength(1),
      );
    });
  });
}

class _LookupApi extends FakeRadarrApi {
  _LookupApi(this.slow);
  final Completer<Result<List<RadarrMovie>>> slow;
  @override
  Future<Result<List<RadarrMovie>>> lookup(String term) {
    if (term == 'old') return slow.future;
    return Future.value(Result.ok([fakeMovie(2, title: 'New Result')]));
  }
}
