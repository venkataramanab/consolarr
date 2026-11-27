// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

const _cookie = 'SID=test-session';

const _torrentsJson =
    '[{"hash":"h1","name":"Example Torrent 1","state":"downloading",'
    '"progress":0.5,"size":1048576,"dlspeed":1024,"upspeed":0,"ratio":0.1,'
    '"eta":600,"added_on":1700000000}]';
const _transferJson =
    '{"dl_info_speed":1024,"up_info_speed":2048,"dl_info_data":1,'
    '"up_info_data":2,"connection_status":"connected"}';

/// A fake qBittorrent behind the real [QBittorrentClient].
class FakeQbit {
  int logins = 0;
  int expireNextDataCalls = 0;

  ResponseBody handle(RequestOptions o) {
    final path = o.uri.path;
    if (path.endsWith('/auth/login')) {
      logins++;
      return ResponseBody.fromString(
        'Ok.',
        200,
        headers: {
          'set-cookie': ['$_cookie; HttpOnly; path=/'],
        },
      );
    }
    final hasCookie = '${o.headers['Cookie']}'.contains(_cookie);
    if (!hasCookie || expireNextDataCalls > 0) {
      if (expireNextDataCalls > 0) expireNextDataCalls--;
      return ResponseBody.fromString('Forbidden', 403);
    }
    if (path.endsWith('/torrents/info')) {
      return ResponseBody.fromString(_torrentsJson, 200);
    }
    if (path.endsWith('/transfer/info')) {
      return ResponseBody.fromString(_transferJson, 200);
    }
    return ResponseBody.fromString('', 404);
  }
}

ProviderContainer containerWith(
  FakeQbit qbit, {
  List<Fault> faults = const [],
  DelayFunction? delay,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://qbit.example'))
    ..httpClientAdapter = FaultInjectingAdapter(
      inner: StubAdapter(qbit.handle),
      faults: faults,
      delay: delay ?? (_) async {},
    );
  final client = QBittorrentClient(
    dio: dio,
    username: 'test-user',
    password: 'test-password',
    parseRunner: <T>(T Function() f) async => f(),
  );
  final c = ProviderContainer(
    overrides: [
      torrentClientProvider.overrideWith((ref) async => client),
      clockProvider.overrideWithValue(() => fixedNow),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('happy path through the real client', () async {
    final qbit = FakeQbit();
    final c = containerWith(qbit);
    final s = await c.read(torrentListProvider.future);
    expect(s.torrents.single.name, 'Example Torrent 1');
    expect(s.transfer!.upSpeed, 2048);
    expect(qbit.logins, 1);
  });

  test('latency does not break loading', () async {
    final waits = <Duration>[];
    final c = containerWith(
      FakeQbit(),
      faults: const [LatencyFault(Duration(seconds: 2))],
      delay: (d) async => waits.add(d),
    );
    final s = await c.read(torrentListProvider.future);
    expect(s.torrents, hasLength(1));
    expect(waits, isNotEmpty);
    expect(waits.every((d) => d == const Duration(seconds: 2)), isTrue);
  });

  test('a dropped connection mid-body is an error without data', () async {
    final c = containerWith(
      FakeQbit(),
      faults: const [ConnectionDropFault(afterBytes: 10)],
    );
    final sub = c.listen(torrentListProvider, (_, _) {});
    await expectLater(
      c.read(torrentListProvider.future),
      throwsA(
        isA<AppError>().having(
          (e) => e.category,
          'category',
          ErrorCategory.networkUnreachable,
        ),
      ),
    );
    sub.close();
  });

  test('a flaky 503 fails first, then a refresh succeeds', () async {
    final c = containerWith(FakeQbit(), faults: const [FlakyFault()]);
    final sub = c.listen(torrentListProvider, (_, _) {});
    await expectLater(
      c.read(torrentListProvider.future),
      throwsA(isA<AppError>()),
    );
    // Each endpoint fails once (login, then the list), so retrying heals it.
    for (var i = 0; i < 3 && c.read(torrentListProvider).value == null; i++) {
      await c.read(torrentListProvider.notifier).refresh();
    }
    expect(c.read(torrentListProvider).value!.torrents, hasLength(1));
    sub.close();
  });

  test('an expired session (403) logs in again once and recovers', () async {
    final qbit = FakeQbit();
    final c = containerWith(qbit);
    final sub = c.listen(torrentListProvider, (_, _) {});
    await c.read(torrentListProvider.future);
    expect(qbit.logins, 1);
    qbit.expireNextDataCalls = 1;
    await c.read(torrentListProvider.notifier).refresh();
    final s = c.read(torrentListProvider).value!;
    expect(s.offline, isFalse);
    expect(qbit.logins, 2);
    sub.close();
  });

  test('a timeout after data keeps the list and goes offline', () async {
    final qbit = FakeQbit();
    final c = containerWith(qbit);
    final sub = c.listen(torrentListProvider, (_, _) {});
    await c.read(torrentListProvider.future);
    // Swap in a failing adapter by exhausting re-login: a persistent 403.
    qbit.expireNextDataCalls = 100;
    await c.read(torrentListProvider.notifier).refresh();
    final s = c.read(torrentListProvider).value!;
    expect(s.offline, isTrue);
    expect(s.torrents, hasLength(1));
    sub.close();
  });
}
