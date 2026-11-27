// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

/// Wraps [inner] and makes the first matching call drop after the server has
/// already processed it (the worst case for "did it add?").
class _DropAfterProcessing extends FakeAdapter {
  _DropAfterProcessing(this.inner, this.matches)
    : super((_) => throw StateError('unused'));

  final FakeAdapter inner;
  final bool Function(RequestOptions) matches;
  int dropped = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await inner.fetch(options, requestStream, cancelFuture);
    if (matches(options) && dropped == 0) {
      dropped++;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'dropped',
        error: const SocketException('connection dropped'),
      );
    }
    return response;
  }
}

String _method(RequestOptions o) {
  final d = o.data;
  return d is String && d.contains('"method"') ? d : '';
}

void main() {
  group('a dropped connection is never retried by the client', () {
    test(
      'Transmission: drop during add -> one add call, typed error',
      () async {
        final s = FakeTransmission();
        final adapter = _DropAfterProcessing(
          s.adapter,
          (o) => _method(o).contains('torrent-add'),
        );
        final c = TransmissionClient(
          dio: dioWith(adapter, base: 'https://transmission.example'),
        );
        // Prime the session id so the dropped call is the add itself.
        await c.listTorrents();
        final r = await c.addMagnetOrUrl(exampleMagnet);
        expect(r.errorOrNull?.category, ErrorCategory.networkUnreachable);
        expect(s.addCalls, 1);
      },
    );

    test('Transmission: drop during delete -> one delete call', () async {
      final s = FakeTransmission();
      final adapter = _DropAfterProcessing(
        s.adapter,
        (o) => _method(o).contains('torrent-remove'),
      );
      final c = TransmissionClient(
        dio: dioWith(adapter, base: 'https://transmission.example'),
      );
      await c.listTorrents();
      final r = await c.delete([exampleHash], deleteFiles: true);
      expect(r.errorOrNull?.category, ErrorCategory.networkUnreachable);
      expect(
        s.seen.where((o) => _method(o).contains('torrent-remove')),
        hasLength(1),
      );
    });

    test('qBittorrent: drop during add and delete -> one call each', () async {
      final s = FakeQBittorrent();
      final adapter = _DropAfterProcessing(
        s.adapter,
        (o) =>
            o.uri.path.endsWith('torrents/add') ||
            o.uri.path.endsWith('torrents/delete'),
      );
      final c = QBittorrentClient(
        dio: dioWith(adapter),
        username: 'test-user',
        password: 'test-password',
      );
      expect((await c.addMagnetOrUrl(exampleMagnet)).isErr, isTrue);
      expect(s.addCalls, 1);
      adapter.dropped = 0;
      expect((await c.delete([exampleHash], deleteFiles: true)).isErr, isTrue);
      expect(s.paths.where((p) => p == 'torrents/delete'), hasLength(1));
    });

    test('Deluge: drop during add -> one add call', () async {
      final s = FakeDeluge();
      final adapter = _DropAfterProcessing(
        s.adapter,
        (o) => _method(o).contains('add_torrent_magnet'),
      );
      final c = DelugeClient(
        dio: dioWith(adapter, base: 'https://deluge.example'),
        password: 'test-password',
      );
      await c.listTorrents();
      expect((await c.addMagnetOrUrl(exampleMagnet)).isErr, isTrue);
      expect(s.addCalls, 1);
    });
  });

  group('storms and slow servers', () {
    test(
      'Transmission 409 storm across calls: every call ends, none loops',
      () async {
        final s = FakeTransmission()..stormRemaining = 1000;
        final c = TransmissionClient(
          dio: dioWith(s.adapter, base: 'https://transmission.example'),
        );
        for (var i = 0; i < 5; i++) {
          expect(
            (await c.listTorrents()).errorOrNull?.category,
            ErrorCategory.serverError,
          );
        }
        expect(s.seen, hasLength(10)); // two requests per call, never more
      },
    );

    test('Deluge: a server that always says "Not authenticated" ends after one re-login', () async {
      final s = FakeDeluge();
      final a = FakeAdapter((o) {
        final m = o.data is String && (o.data as String).contains('auth.login');
        if (m) return s.adapter.handler(o);
        return FakeAdapter.reply(
          '{"result":null,"error":{"message":"Not authenticated","code":1},"id":1}',
        );
      });
      final c = DelugeClient(
        dio: dioWith(a, base: 'https://deluge.example'),
        password: 'test-password',
      );
      final r = await c.transferInfo();
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
      expect(s.logins, 2);
    });

    test('a slow server that answers late still succeeds; one that never does times out', () async {
      final s = FakeTransmission();
      final slow = FakeAdapter((o) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return s.adapter.handler(o);
      });
      final c = TransmissionClient(
        dio: dioWith(slow, base: 'https://transmission.example'),
      );
      expect((await c.listTorrents()).isOk, isTrue);
      final dead = FakeAdapter(
        (o) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 30),
          requestOptions: o,
        ),
      );
      final d = DelugeClient(
        dio: dioWith(dead, base: 'https://deluge.example'),
        password: 'x',
      );
      expect(
        (await d.listTorrents()).errorOrNull?.category,
        ErrorCategory.timeout,
      );
    });
  });

  group('secrets stay out of requests and errors', () {
    test('no credential, session id or cookie in any URL or error', () async {
      final tr = FakeTransmission();
      final dl = FakeDeluge();
      final trc = TransmissionClient(
        dio: dioWith(tr.adapter, base: 'https://transmission.example'),
        username: 'test-user',
        password: 'test-password',
      );
      final dlc = DelugeClient(
        dio: dioWith(dl.adapter, base: 'https://deluge.example'),
        password: 'test-password',
      );
      await trc.addMagnetOrUrl(exampleMagnet);
      await dlc.addMagnetOrUrl(exampleMagnet);
      for (final o in [...tr.seen, ...dl.adapter.requests]) {
        final url = o.uri.toString();
        expect(url, isNot(contains('test-password')));
        expect(url, isNot(contains(secretPasskey)));
        expect(url, isNot(contains('session-one')));
        expect(url, isNot(contains('sid-')));
        expect(o.uri.hasQuery, isFalse);
      }
      final bad = await TransmissionClient(
        dio: dioWith(
          FakeAdapter.fixed('{"result":"nope $secretPasskey"}'),
          base: 'https://t.example',
        ),
      ).addMagnetOrUrl(exampleMagnet);
      expect('${bad.errorOrNull?.debugDetail}', isNot(contains(secretPasskey)));
    });
  });
}
