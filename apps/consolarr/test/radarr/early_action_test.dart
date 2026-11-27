// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A container whose Radarr context resolves only when [gate] completes, as
/// right after app start.
ProviderContainer _slowContext(FakeRadarrApi api, Completer<void> gate) {
  final context = contextFor(api);
  final c = ProviderContainer(
    overrides: [
      ...radarrOverrides(api, includeContext: false),
      radarrContextProvider.overrideWith((ref) async {
        await gate.future;
        return context;
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a grab tapped before the context resolved still completes', () async {
    final api = FakeRadarrApi();
    final gate = Completer<void>();
    final c = _slowContext(api, gate);
    c.listen(grabStatusProvider, (_, _) {});
    final release = fakeRelease('g1', indexerId: 1, title: 'A');
    final done = c.read(grabStatusProvider.notifier).grab(release);
    gate.complete();
    await done;
    expect(
      c.read(grabStatusProvider).values,
      isNot(contains(GrabPhase.grabbing)),
    );
    expect(api.calls, contains('grab g1'));
    expect(c.read(grabStatusProvider).values, [GrabPhase.grabbed]);
  });

  test(
    'a search started before the context resolved still completes',
    () async {
      final api = FakeRadarrApi();
      final gate = Completer<void>();
      final c = _slowContext(api, gate);
      c.listen(searchStatusProvider, (_, _) {});
      final done = c.read(searchStatusProvider.notifier).searchMovie(7);
      gate.complete();
      await done;
      final phases = c.read(searchStatusProvider).values;
      expect(phases, isNotEmpty);
      expect(phases, everyElement(SearchPhase.done));
    },
  );

  test(
    'a failing library isolate clears computing and keeps results',
    () async {
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(3)));
      var fail = false;
      final c = ProviderContainer(
        overrides: [
          ...radarrOverrides(
            api,
            movieRunner: <T>(T Function() compute) async {
              if (fail) throw StateError('isolate died');
              return compute();
            },
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(visibleMoviesProvider, (_, _) {});
      await c.read(movieLibraryProvider.future);
      final before = c.read(visibleMoviesProvider);
      expect(before.computing, isFalse);
      // Force the isolate path for the next computation.
      api.moviesResult = Result.ok(fakeMovies(movieSyncLimit + 1));
      fail = true;
      await c.read(movieLibraryProvider.notifier).refresh();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final after = c.read(visibleMoviesProvider);
      expect(after.computing, isFalse);
      expect(after.movies, before.movies);
    },
  );
}
