// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
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
      ..queueResult = Result.ok([fakeQueueItem(5)]);
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
      ..queueResult = Result.ok([fakeQueueItem(1)]);
    expect(
      await run(
        containerFor(api),
        const SearchTarget.season(seriesId: 1, seasonNumber: 1),
      ),
      isA<SearchGrabbed>(),
    );
    expect(
      await run(containerFor(api), const SearchTarget.series(2)),
      isA<SearchNothingFound>(),
    );
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

    test('5xx on start is reported once, without retrying', () async {
      var requests = 0;
      final inner = StubAdapter((o) {
        requests++;
        return ResponseBody.fromString('', 503);
      });
      final result = await runReal(sessionFor(const [], inner));
      expect(result, isA<SearchFailed>());
      expect(requests, 1);
    });
  });
}
