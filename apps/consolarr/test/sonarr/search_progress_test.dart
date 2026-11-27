// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'support.dart';

const _episode = SearchTarget.episode(5);

ArrCommand _cmd(ArrCommandStatus s) => ArrCommand(id: 1, status: s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerFor(SonarrApi api, {int polls = 4}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...sonarrTestOverrides(api),
        searchPollDelaysProvider.overrideWithValue([
          for (var i = 0; i < polls; i++) Duration.zero,
        ]),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<SearchProgress> run(
    ProviderContainer c, [
    SearchTarget target = _episode,
  ]) async {
    final sub = c.listen(searchProgressProvider(target), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    await c.read(searchProgressProvider(target).notifier).start();
    final result = c.read(searchProgressProvider(target));
    sub.close();
    return result;
  }

  test('searching, then grabbed when the episode is in the queue', () async {
    final api = ScriptedSonarrApi()
      ..commandResults = [
        Result.ok(_cmd(ArrCommandStatus.started)),
        Result.ok(_cmd(ArrCommandStatus.completed)),
      ]
      ..queueSequence = [
        const Result.ok([]),
        Result.ok([fakeQueueItem(5)]),
      ];
    final c = containerFor(api);
    final states = <SearchProgress>[];
    c.listen(searchProgressProvider(_episode), (_, n) => states.add(n));
    await c.read(sonarrSessionProvider.future);
    await c.read(searchProgressProvider(_episode).notifier).start();
    expect(states.first, isA<SearchRunning>());
    expect(states.last, isA<SearchGrabbed>());
    expect(api.count('startCommand'), 1);
    expect(api.count('command'), 2);
    final request = api.sent.first! as ArrCommandRequest;
    expect(request.name, 'EpisodeSearch');
  });

  test('nothing found when the queue has nothing for the target', () async {
    final api = ScriptedSonarrApi()
      ..queueResult = Result.ok([fakeQueueItem(9)]);
    expect(await run(containerFor(api)), isA<SearchNothingFound>());
  });

  test('season and series scopes match on the series and season', () async {
    final api = ScriptedSonarrApi()
      ..queueSequence = [
        const Result.ok([]),
        Result.ok([fakeQueueItem(1)]),
      ];
    expect(
      await run(
        containerFor(api),
        const SearchTarget.season(seriesId: 1, seasonNumber: 1),
      ),
      isA<SearchGrabbed>(),
    );
    api.queueSequence = [
      const Result.ok([]),
      Result.ok([fakeQueueItem(1)]),
    ];
    expect(
      await run(containerFor(api), const SearchTarget.series(2)),
      isA<SearchNothingFound>(),
    );
  });

  test('an item that was already queued is not a fresh grab', () async {
    final api = ScriptedSonarrApi()
      ..queueResult = Result.ok([fakeQueueItem(5)]);
    expect(await run(containerFor(api)), isA<SearchNothingFound>());
    // Same queue before and after, for every scope.
    for (final target in const [
      SearchTarget.season(seriesId: 1, seasonNumber: 1),
      SearchTarget.series(1),
      SearchTarget.missing(),
    ]) {
      expect(await run(containerFor(api), target), isA<SearchNothingFound>());
    }
  });

  test('search all missing reports both outcomes', () async {
    const missing = SearchTarget.missing();
    final found = ScriptedSonarrApi()
      ..queueSequence = [
        Result.ok([fakeQueueItem(1)]),
        Result.ok([fakeQueueItem(1), fakeQueueItem(2, seriesId: 9)]),
      ];
    expect(await run(containerFor(found), missing), isA<SearchGrabbed>());
    final none = ScriptedSonarrApi()
      ..queueResult = Result.ok([fakeQueueItem(1)]);
    expect(await run(containerFor(none), missing), isA<SearchNothingFound>());
  });

  test('an unreadable queue snapshot does not fail the search', () async {
    final api = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.completed))]
      ..queueSequence = [
        const Result.err(AppError(ErrorCategory.timeout)),
        Result.ok([fakeQueueItem(5)]),
      ];
    final c = containerFor(api);
    final result = await run(c);
    expect(api.count('startCommand'), 1, reason: 'the search still starts');
    // Without a baseline the queued episode cannot be told from one that was
    // already there: never a false "found" (nor a false "nothing found").
    expect(result, isNot(isA<SearchGrabbed>()));
    expect(result, isA<SearchTimedOut>());
  });

  test('a server switch mid-search drops the result', () async {
    final gate = Completer<void>();
    final first = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.completed))]
      ..queueSequence = [
        const Result.ok([]),
        Result.ok([fakeQueueItem(5)]),
      ]
      ..hook = (n) => n == 'startCommand' ? gate.future : Future.value();
    final second = ScriptedSonarrApi();
    final servers = SwitchableSonarr(first, second);
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...servers.overrides,
        searchPollDelaysProvider.overrideWithValue([Duration.zero]),
      ],
    );
    addTearDown(c.dispose);
    c.listen(searchProgressProvider(_episode), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    final run = c.read(searchProgressProvider(_episode).notifier).start();
    await Future<void>.delayed(Duration.zero);
    servers.switchToSecond(c);
    await c.read(sonarrSessionProvider.future);
    gate.complete();
    await run;
    // The other server's same-numbered episode shows no result and the old
    // server is not polled.
    expect(c.read(searchProgressProvider(_episode)), isA<SearchIdle>());
    expect(first.count('command'), 0);
    expect(second.count('startCommand'), 0);
  });

  test('polling pauses while the app is locked and resumes after', () async {
    final api = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.completed))];
    final c = containerFor(api, polls: 2);
    c.listen(searchProgressProvider(_episode), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    c.read(testAppLockedProvider.notifier).locked = true;
    final run = c.read(searchProgressProvider(_episode).notifier).start();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(api.count('command'), 0, reason: 'no status poll while locked');
    expect(c.read(searchProgressProvider(_episode)), isA<SearchRunning>());
    c.read(testAppLockedProvider.notifier).locked = false;
    await run;
    expect(api.count('command'), 1);
    expect(c.read(searchProgressProvider(_episode)), isA<SearchNothingFound>());
  });

  test('a lock that never lifts times out after the bounded pause', () async {
    final api = ScriptedSonarrApi();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...sonarrTestOverrides(api),
        searchPollDelaysProvider.overrideWithValue([Duration.zero]),
        searchBackgroundPauseProvider.overrideWithValue((
          step: Duration.zero,
          maxSteps: 3,
        )),
      ],
    );
    addTearDown(c.dispose);
    c.listen(searchProgressProvider(_episode), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    c.read(testAppLockedProvider.notifier).locked = true;
    await c.read(searchProgressProvider(_episode).notifier).start();
    expect(c.read(searchProgressProvider(_episode)), isA<SearchTimedOut>());
    expect(api.count('command'), 0);
  });

  testWidgets('the background pause is bounded', (tester) async {
    final api = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.started))];
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...sonarrTestOverrides(api),
        searchPollDelaysProvider.overrideWithValue([Duration.zero]),
        searchBackgroundPauseProvider.overrideWithValue((
          step: Duration.zero,
          maxSteps: 3,
        )),
      ],
    );
    addTearDown(c.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    c.listen(searchProgressProvider(_episode), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    await tester.runAsync(
      () => c.read(searchProgressProvider(_episode).notifier).start(),
    );
    expect(c.read(searchProgressProvider(_episode)), isA<SearchTimedOut>());
    expect(api.count('command'), 0);
  });

  test('a command that never finishes times out after the poll cap', () async {
    final api = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.started))];
    expect(await run(containerFor(api, polls: 3)), isA<SearchTimedOut>());
    expect(api.count('command'), 3);
  });

  test('a failed command is a failure', () async {
    final api = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.failed))];
    expect(await run(containerFor(api)), isA<SearchFailed>());
  });

  test('start failure is reported and can be retried', () async {
    final api = ScriptedSonarrApi()
      ..startResult = const Result.err(AppError(ErrorCategory.timeout));
    final c = containerFor(api);
    expect(await run(c), isA<SearchFailed>());
    api.startResult = Result.ok(_cmd(ArrCommandStatus.queued));
    expect(await run(c), isA<SearchNothingFound>());
    expect(api.count('startCommand'), 2);
  });

  test('auth failure while polling stops at once', () async {
    final api = ScriptedSonarrApi()
      ..commandResults = [const Result.err(AppError(ErrorCategory.authFailed))];
    expect(await run(containerFor(api)), isA<SearchFailed>());
    expect(api.count('command'), 1);
  });

  test('three poll errors in a row fail; a single one is tolerated', () async {
    final flaky = ScriptedSonarrApi()
      ..commandResults = [
        const Result.err(AppError(ErrorCategory.timeout)),
        Result.ok(_cmd(ArrCommandStatus.completed)),
      ];
    expect(await run(containerFor(flaky)), isA<SearchNothingFound>());
    final dead = ScriptedSonarrApi()
      ..commandResults = [const Result.err(AppError(ErrorCategory.timeout))];
    expect(await run(containerFor(dead, polls: 10)), isA<SearchFailed>());
    expect(dead.count('command'), 3);
  });

  test('a second start while running is ignored', () async {
    final gate = Completer<void>();
    final api = ScriptedSonarrApi()
      ..hook = (n) => n == 'startCommand' ? gate.future : Future.value();
    final c = containerFor(api);
    c.listen(searchProgressProvider(_episode), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    final notifier = c.read(searchProgressProvider(_episode).notifier);
    final first = notifier.start();
    await Future<void>.delayed(Duration.zero);
    await notifier.start();
    gate.complete();
    await first;
    expect(api.count('startCommand'), 1);
  });

  test('leaving the screen stops polling', () async {
    final gate = Completer<void>();
    final api = ScriptedSonarrApi()
      ..commandResults = [Result.ok(_cmd(ArrCommandStatus.started))]
      ..hook = (n) => n == 'command' ? gate.future : Future.value();
    final c = containerFor(api, polls: 50);
    final sub = c.listen(searchProgressProvider(_episode), (_, _) {});
    await c.read(sonarrSessionProvider.future);
    final run = c.read(searchProgressProvider(_episode).notifier).start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    sub.close();
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await run;
    final calls = api.count('command');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(api.count('command'), calls);
    expect(calls, lessThan(50));
  });

  group('over a real client with network faults', () {
    SonarrSession sessionFor(List<Fault> faults, StubAdapter inner) {
      final adapter = FaultInjectingAdapter(inner: inner, faults: faults);
      return SonarrSession(
        api: SonarrClient(dio: fakeConnection(adapter).dio),
        serverId: 'srv1',
        cache: MemoryPayloadCache(),
        clock: DateTime.now,
      );
    }

    ResponseBody json(String body) => ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

    Future<SearchProgress> runReal(SonarrSession session) async {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sonarrSessionProvider.overrideWith((ref) => session),
          searchPollDelaysProvider.overrideWithValue(
            List.filled(6, Duration.zero),
          ),
          clockProvider.overrideWithValue(DateTime.now),
          appLockedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c.dispose);
      c.listen(searchProgressProvider(_episode), (_, _) {});
      await c.read(sonarrSessionProvider.future);
      await c.read(searchProgressProvider(_episode).notifier).start();
      return c.read(searchProgressProvider(_episode));
    }

    test('connection dropped on every poll: fails after three tries', () async {
      var polls = 0;
      final inner = StubAdapter((o) {
        if (o.method == 'POST') {
          return json('{"id":1,"status":"queued"}');
        }
        if (o.uri.path.endsWith('/queue')) {
          return json(
            '{"page":1,"pageSize":200,"totalRecords":0,"records":[]}',
          );
        }
        polls++;
        throw DioException.connectionError(requestOptions: o, reason: 'drop');
      });
      final result = await runReal(sessionFor(const [], inner));
      expect(result, isA<SearchFailed>());
      expect(polls, 3);
    });

    test('malformed command body is a failure, not a crash', () async {
      final inner = StubAdapter((o) => json('not json'));
      final result = await runReal(sessionFor(const [], inner));
      expect(result, isA<SearchFailed>());
    });

    test('5xx is reported once per request, without retrying', () async {
      var requests = 0;
      final inner = StubAdapter((o) {
        requests++;
        return ResponseBody.fromString('', 503);
      });
      final result = await runReal(sessionFor(const [], inner));
      expect(result, isA<SearchFailed>());
      // The queue snapshot (which no longer blocks the search) and the
      // start command: one request each, no retries.
      expect(requests, 2);
    });
  });
}
