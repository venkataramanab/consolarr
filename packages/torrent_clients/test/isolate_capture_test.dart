// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

/// An adapter that cannot be sent to another isolate (it owns a
/// [ReceivePort]), like the real `HttpClient` behind a secure Dio. A closure
/// that captures the client therefore fails in `Isolate.run`.
class _UnsendableAdapter implements HttpClientAdapter {
  _UnsendableAdapter(this._inner);

  final FakeAdapter _inner;
  final ReceivePort _port = ReceivePort();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _inner.fetch(options, requestStream, cancelFuture);

  @override
  void close({bool force = false}) => _port.close();
}

Dio _dio(FakeAdapter inner, String base) {
  final dio = Dio(BaseOptions(baseUrl: base))
    ..httpClientAdapter = _UnsendableAdapter(inner);
  addTearDown(() => dio.close(force: true));
  return dio;
}

/// More than 64 KB of list JSON for every kind.
void _fill(FakeServer s) {
  for (var i = 0; i < 1200; i++) {
    s.torrents.add(
      FakeTorrent(
        i.toRadixString(16).padLeft(40, '0'),
        'Example Linux ISO number $i with a padded name',
      ),
    );
  }
}

void main() {
  test('qBittorrent: a list over 64 KB parses on a real isolate', () async {
    final s = FakeQBittorrent();
    _fill(s);
    final c = QBittorrentClient(
      dio: _dio(s.adapter, 'https://qbit.example'),
      username: 'u',
      password: 'p',
    );
    final r = await c.listTorrents();
    expect(r.errorOrNull?.category, isNull);
    expect(r.valueOrNull, hasLength(1201));
  });

  test('Transmission: a list over 64 KB parses on a real isolate', () async {
    final s = FakeTransmission();
    _fill(s);
    final c = TransmissionClient(dio: _dio(s.adapter, 'https://tr.example'));
    final r = await c.listTorrents();
    expect(r.errorOrNull?.category, isNull);
    expect(r.valueOrNull, hasLength(1201));
  });

  test('Deluge: a list over 64 KB parses on a real isolate', () async {
    final s = FakeDeluge();
    _fill(s);
    final c = DelugeClient(
      dio: _dio(s.adapter, 'https://deluge.example'),
      password: 'test-password',
    );
    final r = await c.listTorrents();
    expect(r.errorOrNull?.category, isNull);
    expect(r.valueOrNull, hasLength(1201));
  });
}
