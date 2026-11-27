// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

const _body = '{"version":"4.0.0.0"}';

Dio _dio(List<Fault> faults, {List<Duration>? delays}) {
  final adapter = FaultInjectingAdapter(
    inner: StubAdapter.json(_body),
    faults: faults,
    delay: (d) async => delays?.add(d),
  );
  return Dio(BaseOptions(baseUrl: 'https://sonarr.example'))
    ..httpClientAdapter = adapter;
}

void main() {
  test('passes requests through when no faults are configured', () async {
    final r = await _dio([]).get<Map<String, Object?>>('/api/v3/system/status');
    expect(r.statusCode, 200);
    expect(r.data?['version'], '4.0.0.0');
  });

  test('latency waits before delegating', () async {
    final delays = <Duration>[];
    final r = await _dio([
      const LatencyFault(Duration(milliseconds: 750)),
    ], delays: delays).get<String>('/x');
    expect(r.statusCode, 200);
    expect(delays, [const Duration(milliseconds: 750)]);
  });

  test('timeout fault fails with the requested Dio timeout type', () async {
    for (final entry in {
      TimeoutKind.connect: DioExceptionType.connectionTimeout,
      TimeoutKind.send: DioExceptionType.sendTimeout,
      TimeoutKind.receive: DioExceptionType.receiveTimeout,
    }.entries) {
      await expectLater(
        _dio([TimeoutFault(kind: entry.key)]).get<String>('/x'),
        throwsA(isA<DioException>().having((e) => e.type, 'type', entry.value)),
      );
    }
  });

  test('timeout on first attempts only: a retry succeeds', () async {
    final dio = _dio([const TimeoutFault(firstAttempts: 2)]);
    await expectLater(dio.get<String>('/x'), throwsA(isA<DioException>()));
    await expectLater(dio.get<String>('/x'), throwsA(isA<DioException>()));
    expect((await dio.get<String>('/x')).statusCode, 200);
  });

  test('connection drop fails to connect', () async {
    await expectLater(
      _dio([const ConnectionDropFault()]).get<String>('/x'),
      throwsA(
        isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.connectionError)
            .having((e) => e.error, 'error', isA<SocketException>()),
      ),
    );
  });

  test('connection drop mid-body truncates the response', () async {
    final dio = _dio([const ConnectionDropFault(afterBytes: 5)]);
    await expectLater(
      dio
          .get<ResponseBody>(
            '/x',
            options: Options(responseType: ResponseType.stream),
          )
          .then((r) => r.data!.stream.toList()),
      throwsA(isA<SocketException>()),
    );
  });

  test('flaky server: first N requests return 503 then recover', () async {
    final dio = _dio([const FlakyFault(failFirst: 2)])
      ..options.validateStatus = (_) => true;
    expect((await dio.get<String>('/x')).statusCode, 503);
    expect((await dio.get<String>('/x')).statusCode, 503);
    expect((await dio.get<String>('/x')).statusCode, 200);
    // Attempts are counted per endpoint.
    expect((await dio.get<String>('/other')).statusCode, 503);
  });

  test('slow body delivers the full payload in delayed chunks', () async {
    final delays = <Duration>[];
    final dio = _dio([
      const SlowBodyFault(
        chunkSize: 4,
        chunkDelay: Duration(milliseconds: 100),
      ),
    ], delays: delays);
    final r = await dio.get<ResponseBody>(
      '/x',
      options: Options(responseType: ResponseType.stream),
    );
    final bytes = await r.data!.stream.expand((c) => c).toList();
    expect(utf8.decode(bytes), _body);
    expect(delays, hasLength((_body.length / 4).ceil()));
    expect(delays.toSet(), {const Duration(milliseconds: 100)});
  });

  test('faults compose in order', () async {
    final delays = <Duration>[];
    final dio = _dio([
      const LatencyFault(Duration(milliseconds: 10)),
      const FlakyFault(),
    ], delays: delays)..options.validateStatus = (_) => true;
    expect((await dio.get<String>('/x')).statusCode, 503);
    expect(delays, [const Duration(milliseconds: 10)]);
    expect((await dio.get<String>('/x')).statusCode, 200);
  });

  test('counts requests', () async {
    final adapter = FaultInjectingAdapter(inner: StubAdapter.json(_body));
    final dio = Dio()..httpClientAdapter = adapter;
    await dio.get<String>('https://a.example/1');
    await dio.get<String>('https://a.example/2');
    expect(adapter.requestCount, 2);
  });
}
