// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/sonarr/application/queue_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';

const _choice = ArrQueueRemovalChoice(
  removeFromClient: true,
  blocklist: ArrBlocklistChoice.blocklistOnly,
);

/// Applies [inner] to one HTTP method only (the removal), so reading the queue
/// back still works.
class _OnlyMethod extends Fault {
  const _OnlyMethod(this.method, this.inner);

  final String method;
  final Fault inner;

  @override
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async =>
      options.method == method ? inner.before(options, attempt, delay) : null;
}

/// The server acts on the request, then the connection dies before the
/// answer arrives.
class _ActThenDrop extends Fault {
  _ActThenDrop(this.onAct);

  final void Function() onAct;

  @override
  Future<ResponseBody?> before(
    RequestOptions options,
    int attempt,
    DelayFunction delay,
  ) async {
    if (options.method == 'DELETE') {
      onAct();
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('dropped'),
      );
    }
    return null;
  }
}

class _Server {
  bool removed = false;
  int deletes = 0;
  int status = 200;
  String? queueBody;
  final deleteQueries = <Map<String, String>>[];

  ResponseBody handle(RequestOptions o) {
    if (o.method == 'DELETE') {
      deletes++;
      deleteQueries.add(o.uri.queryParameters);
      if (status == 200) removed = true;
      return ResponseBody.fromString('', status);
    }
    final body =
        queueBody ??
        jsonEncode({
          'page': 1,
          'pageSize': 200,
          'totalRecords': removed ? 0 : 1,
          'records': removed
              ? []
              : [
                  {
                    'id': 7,
                    'title': 'Example.Show.S01E01',
                    'status': 'downloading',
                    'size': 100,
                    'sizeleft': 50,
                    'seriesId': 1,
                    'series': {'id': 1, 'title': 'Example Show'},
                  },
                ],
        });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<ProviderContainer> _start(_Server server, List<Fault> faults) async {
  final adapter = FaultInjectingAdapter(
    inner: StubAdapter(server.handle),
    faults: faults,
    delay: (_) async {},
  );
  final dio = Dio(BaseOptions(baseUrl: 'https://sonarr.example'))
    ..httpClientAdapter = adapter;
  final client = SonarrClient(
    dio: dio,
    parseRunner: <T>(T Function() f) async => f(),
  );
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...sonarrTestOverrides(client),
      queuePollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ],
  );
  addTearDown(c.dispose);
  c.listen(queueProvider, (_, _) {});
  await c.read(queueProvider.future);
  return c;
}

void main() {
  test('the removal request carries the choices, no key in the URL', () async {
    final server = _Server();
    final c = await _start(server, const []);
    final error = await c.read(queueProvider.notifier).remove(7, _choice);
    expect(error, isNull);
    final q = server.deleteQueries.single;
    expect(q['removeFromClient'], 'true');
    expect(q['blocklist'], 'true');
    expect(q['skipRedownload'], 'true');
    expect(q.keys.join(), isNot(contains('apikey')));
    expect((c.read(queueProvider).value! as QueueData).items, isEmpty);
  });

  test('timeout: reported, item stays, retry sends one more request', () async {
    final server = _Server();
    final c = await _start(server, const [
      _OnlyMethod('DELETE', TimeoutFault(firstAttempts: 1)),
    ]);
    final first = await c.read(queueProvider.notifier).remove(7, _choice);
    expect(first?.category, ErrorCategory.timeout);
    expect((c.read(queueProvider).value! as QueueData).items, hasLength(1));
    expect(server.deletes, 0);
    final second = await c.read(queueProvider.notifier).remove(7, _choice);
    expect(second, isNull);
    expect(server.deletes, 1);
  });

  test(
    'a drop after the server acted is success, not a second submit',
    () async {
      final server = _Server();
      final c = await _start(server, [
        _ActThenDrop(() => server.removed = true),
      ]);
      final error = await c.read(queueProvider.notifier).remove(7, _choice);
      expect(error, isNull, reason: 'the re-read shows the item is gone');
      expect(server.deletes, 0, reason: 'no repeated DELETE was sent');
      expect((c.read(queueProvider).value! as QueueData).items, isEmpty);
    },
  );

  test(
    'a drop before the server acted keeps the item and allows retry',
    () async {
      final server = _Server();
      final c = await _start(server, [
        _OnlyMethod('DELETE', const ConnectionDropFault()),
      ]);
      final error = await c.read(queueProvider.notifier).remove(7, _choice);
      expect(error?.category, ErrorCategory.networkUnreachable);
      expect((c.read(queueProvider).value! as QueueData).items, hasLength(1));
    },
  );

  test('401 is auth_failed and the item stays', () async {
    final server = _Server()..status = 401;
    final c = await _start(server, const []);
    final error = await c.read(queueProvider.notifier).remove(7, _choice);
    expect(error?.category, ErrorCategory.authFailed);
    expect((c.read(queueProvider).value! as QueueData).items, hasLength(1));
  });

  test('5xx is server_error', () async {
    final server = _Server()..status = 503;
    final c = await _start(server, const []);
    final error = await c.read(queueProvider.notifier).remove(7, _choice);
    expect(error?.category, ErrorCategory.serverError);
  });

  test('a malformed queue answer on re-read keeps the removal error', () async {
    final server = _Server()..status = 500;
    final c = await _start(server, const []);
    server.queueBody = '<html>not json</html>';
    final error = await c.read(queueProvider.notifier).remove(7, _choice);
    expect(error?.category, ErrorCategory.serverError);
  });

  test('a malformed first queue answer is parse_error', () async {
    final server = _Server()..queueBody = '{"records": "nope"}';
    final adapter = FaultInjectingAdapter(inner: StubAdapter(server.handle));
    final dio = Dio(BaseOptions(baseUrl: 'https://sonarr.example'))
      ..httpClientAdapter = adapter;
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sonarrSessionProvider.overrideWith(
          (ref) async => SonarrSession(
            api: SonarrClient(
              dio: dio,
              parseRunner: <T>(T Function() f) async => f(),
            ),
            serverId: 's',
            cache: MemoryPayloadCache(),
            clock: DateTime.now,
          ),
        ),
        queuePollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(queueProvider, (_, _) {});
    final state = await c.read(queueProvider.future);
    expect(state, isA<QueueFailure>());
    expect((state as QueueFailure).error.category, ErrorCategory.parseError);
  });
}
