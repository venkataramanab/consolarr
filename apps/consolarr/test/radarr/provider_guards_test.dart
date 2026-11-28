// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'switching.dart';
import '../support/fake_hex.dart';

void main() {
  group('I2: search state is keyed by server and movie', () {
    test('a server switch does not leak a running search', () async {
      final a = GatedApi()..commandScript = [ArrCommandStatus.started];
      a.commandGate = Completer<void>();
      final b = GatedApi();
      final (c, holder) = switchingContainer(serverContext(a, 'srvA'));
      c.listen(searchStatusProvider, (_, _) {});
      c.listen(searchPhaseProvider(7), (_, _) {});
      await c.read(radarrContextProvider.future);

      final running = c.read(searchStatusProvider.notifier).searchMovie(7);
      await settle();
      expect(c.read(searchPhaseProvider(7)), isNotNull);

      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(radarrContextProvider.future);
      await settle();
      // Server B has no search for movie 7, although A is still polling.
      expect(c.read(searchPhaseProvider(7)), isNull);
      expect(c.read(searchStatusProvider), isEmpty);

      a.commandGate!.complete();
      await running;
      await settle();
      expect(c.read(searchPhaseProvider(7)), isNull);
      expect(c.read(searchStatusProvider), isEmpty);
      expect(b.calls, isEmpty);
    });

    test('the same movie number on two servers is two searches', () async {
      final a = GatedApi();
      final b = GatedApi();
      final (c, holder) = switchingContainer(serverContext(a, 'srvA'));
      c.listen(searchStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      await c.read(searchStatusProvider.notifier).searchMovie(7);
      expect(c.read(searchStatusProvider).keys, [('srvA', 7)]);

      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(radarrContextProvider.future);
      await settle();
      await c.read(searchStatusProvider.notifier).searchMovie(7);
      expect(c.read(searchStatusProvider).keys, [('srvB', 7)]);
      expect(a.calls, ['search [7]']);
      expect(b.calls, ['search [7]']);
    });
  });

  group('L5: polls are cancelled', () {
    test('leaving the screen (no listener left) stops polling', () async {
      final api = GatedApi()..commandScript = [ArrCommandStatus.started];
      final (c, _) = switchingContainer(
        serverContext(api, 'srvA'),
        pollInterval: const Duration(milliseconds: 10),
      );
      final sub = c.listen(searchStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      unawaited(c.read(searchStatusProvider.notifier).searchMovie(7));
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(api.commandCalls, greaterThan(0));
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final after = api.commandCalls;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(api.commandCalls, after);
    });

    test('a server switch stops polling the old server', () async {
      final a = GatedApi()..commandScript = [ArrCommandStatus.started];
      final b = GatedApi();
      final (c, holder) = switchingContainer(
        serverContext(a, 'srvA'),
        pollInterval: const Duration(milliseconds: 10),
      );
      c.listen(searchStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      unawaited(c.read(searchStatusProvider.notifier).searchMovie(7));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(radarrContextProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final after = a.commandCalls;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(a.commandCalls, after);
    });
  });

  group('I3: writes that finish after a server switch are dropped', () {
    test('MovieDetailNotifier.save', () async {
      final a = GatedApi(moviesResult: Result.ok([fakeMovie(7, title: 'A')]))
        ..updateGate = Completer<void>();
      final b = GatedApi(moviesResult: Result.ok([fakeMovie(7, title: 'B')]));
      final (c, holder) = switchingContainer(serverContext(a, 'srvA'));
      c.listen(movieDetailProvider(7), (_, _) {});
      c.listen(movieLibraryProvider, (_, _) {});
      await c.read(movieDetailProvider(7).future);
      await c.read(movieLibraryProvider.future);

      final saving = c
          .read(movieDetailProvider(7).notifier)
          .save(monitored: false);
      await settle();
      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(movieDetailProvider(7).future);
      await c.read(movieLibraryProvider.future);

      a.updateGate!.complete();
      expect(await saving, isNull);
      await settle();
      final detail =
          c.read(movieDetailProvider(7)).value! as RadarrData<RadarrMovie>;
      expect(detail.value.title, 'B');
      expect(detail.value.monitored, isTrue);
      final library =
          c.read(movieLibraryProvider).value! as RadarrData<List<RadarrMovie>>;
      expect(library.value.single.title, 'B');
      expect(library.value.single.monitored, isTrue);
    });

    test('QueueNotifier.remove', () async {
      final a = GatedApi()
        ..queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(2)])
        ..removeGate = Completer<void>();
      final b = GatedApi()
        ..queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(3)]);
      final (c, holder) = switchingContainer(serverContext(a, 'srvA'));
      c.listen(queueProvider, (_, _) {});
      await c.read(queueProvider.future);

      final removing = c
          .read(queueProvider.notifier)
          .remove(
            fakeQueueItem(1),
            removeFromClient: false,
            blocklist: ArrBlocklistChoice.none,
          );
      await settle();
      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(queueProvider.future);

      a.removeGate!.complete();
      expect(await removing, isNull);
      await settle();
      final state =
          c.read(queueProvider).value! as RadarrData<List<ArrQueueItem>>;
      // Server B's item 1 is still there: A's removal is not applied to it.
      expect([for (final i in state.value) i.id], [1, 3]);
    });
  });

  group('I4: a slow first load cannot take over after a switch', () {
    test('the newer build keeps the notifier and its context', () async {
      final a = GatedApi(moviesResult: Result.ok([fakeMovie(1, title: 'A')]))
        ..moviesGate = Completer<void>();
      final b = GatedApi(moviesResult: Result.ok([fakeMovie(2, title: 'B')]));
      final (c, holder) = switchingContainer(serverContext(a, 'srvA'));
      c.listen(movieLibraryProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      await settle();

      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(radarrContextProvider.future);
      await settle();
      final fresh = await c.read(movieLibraryProvider.future);
      expect((fresh as RadarrData<List<RadarrMovie>>).value.single.title, 'B');

      a.moviesGate!.complete();
      await settle();
      // A's answer did not replace the state or the notifier's context.
      final after =
          c.read(movieLibraryProvider).value! as RadarrData<List<RadarrMovie>>;
      expect(after.value.single.title, 'B');
      final callsA = a.moviesCalls;
      await c.read(movieLibraryProvider.notifier).refresh();
      expect(a.moviesCalls, callsA);
      expect(b.moviesCalls, greaterThan(1));
    });
  });

  group('I5: a search that is still running is not a failure', () {
    test(
      'the cap ends as stillRunning and refreshes queue and library',
      () async {
        final api = GatedApi(moviesResult: Result.ok(fakeMovies(2)))
          ..commandScript = [ArrCommandStatus.started];
        final (c, _) = switchingContainer(serverContext(api, 'srvA'));
        c.listen(searchStatusProvider, (_, _) {});
        c.listen(queueProvider, (_, _) {});
        c.listen(movieLibraryProvider, (_, _) {});
        await c.read(queueProvider.future);
        await c.read(movieLibraryProvider.future);
        final queueBefore = api.queueCalls;
        final libraryBefore = api.moviesCalls;

        await c.read(searchStatusProvider.notifier).searchMovie(7);
        await settle();
        expect(api.commandCalls, maxCommandPolls);
        expect(
          c.read(searchStatusProvider)[('srvA', 7)],
          SearchPhase.stillRunning,
        );
        expect(api.queueCalls, queueBefore + 1);
        expect(api.moviesCalls, libraryBefore + 1);
      },
    );

    test('a completed search refreshes queue and library once', () async {
      final api = GatedApi(moviesResult: Result.ok(fakeMovies(2)));
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      c.listen(searchStatusProvider, (_, _) {});
      c.listen(queueProvider, (_, _) {});
      c.listen(movieLibraryProvider, (_, _) {});
      await c.read(queueProvider.future);
      await c.read(movieLibraryProvider.future);
      final queueBefore = api.queueCalls;
      final libraryBefore = api.moviesCalls;

      await c.read(searchStatusProvider.notifier).searchMovie(7);
      await settle();
      expect(c.read(searchStatusProvider)[('srvA', 7)], SearchPhase.done);
      expect(api.queueCalls, queueBefore + 1);
      expect(api.moviesCalls, libraryBefore + 1);
    });

    test('a failed search does not refresh', () async {
      final api = GatedApi()..commandScript = [ArrCommandStatus.failed];
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      c.listen(searchStatusProvider, (_, _) {});
      c.listen(queueProvider, (_, _) {});
      await c.read(queueProvider.future);
      final before = api.queueCalls;
      await c.read(searchStatusProvider.notifier).searchMovie(7);
      await settle();
      expect(c.read(searchStatusProvider)[('srvA', 7)], SearchPhase.failed);
      expect(api.queueCalls, before);
    });
  });

  group('M1: a grab that may have been sent is never repeated by itself', () {
    final guid = fakeHex(32, seed: 10);

    for (final category in [
      ErrorCategory.timeout,
      ErrorCategory.networkUnreachable,
    ]) {
      test(
        '${category.code} leaves it maybeSent; a second call sends nothing',
        () async {
          final api = GatedApi()..grabResult = Result.err(AppError(category));
          final (c, _) = switchingContainer(serverContext(api, 'srvA'));
          c.listen(grabStatusProvider, (_, _) {});
          await c.read(radarrContextProvider.future);
          final r = fakeRelease(guid);
          final n = c.read(grabStatusProvider.notifier);
          await n.grab(r);
          expect(c.read(grabStatusProvider)[grabKey(r)], GrabPhase.maybeSent);
          await n.grab(r);
          await n.grab(r);
          expect(api.grabCalls, 1);

          api.grabResult = const Result.ok(null);
          await n.grab(r, confirmedResend: true);
          expect(api.grabCalls, 2);
          expect(c.read(grabStatusProvider)[grabKey(r)], GrabPhase.grabbed);
          await n.grab(r, confirmedResend: true);
          expect(api.grabCalls, 2, reason: 'a grabbed release is not re-sent');
        },
      );
    }

    test(
      'an answer from the server is a plain failure and can be retried',
      () async {
        final api = GatedApi()
          ..grabResult = const Result.err(AppError(ErrorCategory.authFailed));
        final (c, _) = switchingContainer(serverContext(api, 'srvA'));
        c.listen(grabStatusProvider, (_, _) {});
        await c.read(radarrContextProvider.future);
        final r = fakeRelease(guid);
        final n = c.read(grabStatusProvider.notifier);
        await n.grab(r);
        expect(c.read(grabStatusProvider)[grabKey(r)], GrabPhase.failed);
        api.grabResult = const Result.ok(null);
        await n.grab(r);
        expect(c.read(grabStatusProvider)[grabKey(r)], GrabPhase.grabbed);
      },
    );

    Future<(ProviderContainer, GatedApi)> maybeSent(ArrRelease r) async {
      final api = GatedApi()
        ..grabResult = const Result.err(AppError(ErrorCategory.timeout));
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      c.listen(grabStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      await c.read(grabStatusProvider.notifier).grab(r);
      return (c, api);
    }

    test('confirmQueued finds it by download id', () async {
      final r = fakeRelease(guid, title: 'Some.Release');
      final (c, api) = await maybeSent(r);
      api.queueResult = Result.ok([
        fakeQueueItem(
          5,
          movieId: 7,
          title: 'Other.Name',
          downloadId: 'ABCDEF0123456789ABCDEF',
        ),
      ]);
      final found = await c
          .read(grabStatusProvider.notifier)
          .confirmQueued(r, 7);
      expect(found, isTrue);
      expect(c.read(grabStatusProvider)[grabKey(r)], GrabPhase.grabbed);
    });

    test('confirmQueued falls back to the title, ignoring case', () async {
      final r = fakeRelease(guid, title: 'Some.Release.2024');
      final (c, api) = await maybeSent(r);
      api.queueResult = Result.ok([
        fakeQueueItem(5, movieId: 7, title: ' some.release.2024 '),
      ]);
      expect(
        await c.read(grabStatusProvider.notifier).confirmQueued(r, 7),
        isTrue,
      );
    });

    test(
      'not queued, queue unreadable, other movie: asks before re-sending',
      () async {
        final r = fakeRelease(guid, title: 'Some.Release.2024');
        final (c, api) = await maybeSent(r);
        final n = c.read(grabStatusProvider.notifier);
        api.queueResult = Result.ok([fakeQueueItem(5, title: 'Unrelated')]);
        expect(await n.confirmQueued(r, 7), isFalse);
        api.queueResult = const Result.err(AppError(ErrorCategory.timeout));
        expect(await n.confirmQueued(r, 7), isFalse);
        api.queueResult = Result.ok([
          fakeQueueItem(5, movieId: 8, title: 'Some.Release.2024'),
        ]);
        expect(await n.confirmQueued(r, 7), isFalse);
        expect(c.read(grabStatusProvider)[grabKey(r)], GrabPhase.maybeSent);
      },
    );

    test(
      'confirmQueued is false for a release that is not maybeSent',
      () async {
        final api = GatedApi()
          ..queueResult = Result.ok([fakeQueueItem(5, title: 'X')]);
        final (c, _) = switchingContainer(serverContext(api, 'srvA'));
        c.listen(grabStatusProvider, (_, _) {});
        await c.read(radarrContextProvider.future);
        expect(
          await c
              .read(grabStatusProvider.notifier)
              .confirmQueued(fakeRelease(guid, title: 'X'), 7),
          isFalse,
        );
        expect(api.queueCalls, 0);
      },
    );

    test('a reopened sheet shows queued releases as grabbed', () async {
      final queued = fakeRelease('g1', title: 'Queued.Release');
      final other = fakeRelease('g2', title: 'Other.Release');
      final api = GatedApi()
        ..queueResult = Result.ok([
          fakeQueueItem(5, movieId: 7, title: 'Queued.Release'),
        ]);
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      c.listen(grabStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      final n = c.read(grabStatusProvider.notifier);
      await n.syncWithQueue([queued, other], 7);
      expect(c.read(grabStatusProvider)[grabKey(queued)], GrabPhase.grabbed);
      expect(c.read(grabStatusProvider).containsKey(grabKey(other)), isFalse);
      await n.grab(queued);
      expect(api.grabCalls, 0);
    });

    test('grab state does not survive a server switch', () async {
      final a = GatedApi()..grabGate = Completer<void>();
      final b = GatedApi();
      final (c, holder) = switchingContainer(serverContext(a, 'srvA'));
      c.listen(grabStatusProvider, (_, _) {});
      await c.read(radarrContextProvider.future);
      final r = fakeRelease('g1');
      final sending = c.read(grabStatusProvider.notifier).grab(r);
      await settle();
      c.read(holder.notifier).activate(serverContext(b, 'srvB'));
      await c.read(radarrContextProvider.future);
      await settle();
      a.grabGate!.complete();
      await sending;
      await settle();
      expect(c.read(grabStatusProvider), isEmpty);
    });
  });

  group('L4: adding a movie after a timeout', () {
    AddMovieRequest request() => AddMovieRequest(
      lookup: const RadarrMovie(
        id: 0,
        title: 'Example Movie',
        sortTitle: 'example movie',
        tmdbId: 99,
      ),
      qualityProfileId: 1,
      rootFolderPath: '/movies',
      minimumAvailability: MinimumAvailability.released,
      monitored: true,
    );

    test('found in the refreshed library: done, no second request', () async {
      final api = GatedApi(
        moviesResult: const Result.ok([
          RadarrMovie(
            id: 5,
            title: 'Example Movie',
            sortTitle: 'example movie',
            tmdbId: 99,
          ),
        ]),
      )..addResult = const Result.err(AppError(ErrorCategory.timeout));
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      await c.read(radarrContextProvider.future);
      final error = await c.read(addMovieActionProvider)(request());
      expect(error, isNull);
      expect(api.addCalls, 1);
      expect(api.moviesCalls, 1);
    });

    test('not in the library: the timeout is returned', () async {
      final api = GatedApi()
        ..addResult = const Result.err(AppError(ErrorCategory.timeout));
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      await c.read(radarrContextProvider.future);
      final error = await c.read(addMovieActionProvider)(request());
      expect(error?.category, ErrorCategory.timeout);
      expect(api.moviesCalls, 1);
    });

    test('a plain server answer does not read the library', () async {
      final api = GatedApi()
        ..addResult = const Result.err(AppError(ErrorCategory.authFailed));
      final (c, _) = switchingContainer(serverContext(api, 'srvA'));
      await c.read(radarrContextProvider.future);
      final error = await c.read(addMovieActionProvider)(request());
      expect(error?.category, ErrorCategory.authFailed);
      expect(api.moviesCalls, 0);
    });
  });
}
