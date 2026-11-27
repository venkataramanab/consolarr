// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

const _movies = '[{"id":1,"title":"Example Movie"}]';
const _release = RadarrRelease(guid: 'g', indexerId: 1, title: 'Example.Rel');

Future<void> _noDelay(Duration _) async {}

({RadarrClient client, FaultInjectingAdapter adapter}) _client(
  List<Fault> faults, {
  String body = _movies,
  int status = 200,
}) {
  final adapter = FaultInjectingAdapter(
    inner: StubAdapter(
      (o) => ResponseBody.fromString(
        body,
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    ),
    faults: faults,
    delay: _noDelay,
  );
  final dio = Dio(BaseOptions(baseUrl: 'https://radarr.example'))
    ..httpClientAdapter = adapter;
  return (
    client: RadarrClient(
      dio: dio,
      parseRunner: <T>(T Function() c) async => c(),
    ),
    adapter: adapter,
  );
}

void main() {
  final calls = <String, Future<Result<Object?>> Function(RadarrClient)>{
    'library': (c) => c.movies(),
    'automatic search': (c) => c.searchMovies([1]),
    'grab': (c) => c.grab(_release),
    'queue removal': (c) => c.removeQueueItem(
      1,
      removeFromClient: true,
      blocklist: ArrBlocklistChoice.none,
    ),
  };

  for (final entry in calls.entries) {
    group(entry.key, () {
      test(
        'timeout is timeout, with one request only (no blind retry)',
        () async {
          final c = _client([const TimeoutFault()]);
          final r = await entry.value(c.client);
          expect(r.errorOrNull?.category, ErrorCategory.timeout);
          expect(c.adapter.requestCount, 1);
        },
      );

      test('dropped connection is network_unreachable', () async {
        final c = _client([const ConnectionDropFault()]);
        final r = await entry.value(c.client);
        expect(r.errorOrNull?.category, ErrorCategory.networkUnreachable);
        expect(c.adapter.requestCount, 1);
      });

      test('401 is auth_failed', () async {
        final r = await entry.value(_client(const [], status: 401).client);
        expect(r.errorOrNull?.category, ErrorCategory.authFailed);
      });

      test('5xx is server_error', () async {
        final r = await entry.value(_client(const [], status: 503).client);
        expect(r.errorOrNull?.category, ErrorCategory.serverError);
      });

      test('a slow body still completes', () async {
        final c = _client([
          const SlowBodyFault(chunkSize: 4, chunkDelay: Duration(seconds: 1)),
        ], body: '{"id":1,"status":"queued"}');
        final r = await entry.value(c.client);
        // The shape differs per call; the point is that it does not hang or
        // throw.
        expect(r, isA<Result<Object?>>());
      });
    });
  }

  test('malformed bodies are parse_error on every read', () async {
    final c = _client(const [], body: '{not json');
    expect(
      (await c.client.movies()).errorOrNull?.category,
      ErrorCategory.parseError,
    );
    expect(
      (await c.client.queue()).errorOrNull?.category,
      ErrorCategory.parseError,
    );
    expect(
      (await c.client.releases(1)).errorOrNull?.category,
      ErrorCategory.parseError,
    );
    expect(
      (await c.client.searchMovies([1])).errorOrNull?.category,
      ErrorCategory.parseError,
    );
  });

  test('an oversized reply is mapped, not thrown', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://radarr.example'))
      ..httpClientAdapter = StubAdapter(
        (o) => throw DioException(
          requestOptions: o,
          error: const AppError(ErrorCategory.responseTooLarge),
        ),
      );
    final r = await RadarrClient(dio: dio).movies();
    expect(r.errorOrNull?.category, ErrorCategory.responseTooLarge);
  });

  test('the API key never appears in any URL, header copy or body', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://radarr.example'))
      ..options.headers['X-Api-Key'] = 'KEY-123'
      ..httpClientAdapter = StubAdapter((o) {
        requests.add(o);
        return ResponseBody.fromString('[]', 200);
      });
    final c = RadarrClient(dio: dio);
    await c.movies();
    await c.queue();
    await c.releases(1);
    await c.lookup('tmdb:1');
    await c.calendar(DateTime.utc(2026), DateTime.utc(2026, 2));
    await c.grab(_release);
    await c.removeQueueItem(
      1,
      removeFromClient: false,
      blocklist: ArrBlocklistChoice.none,
    );
    for (final o in requests) {
      expect(o.uri.toString(), isNot(contains('KEY-123')));
      expect(jsonEncode(o.data), isNot(contains('KEY-123')));
      expect(o.uri.userInfo, isEmpty);
    }
  });
}
