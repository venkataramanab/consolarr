// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

Future<T> _inline<T>(T Function() work) async => work();

TransmissionClient _client(
  FakeTransmission s, {
  String base = 'https://transmission.example',
}) => TransmissionClient(
  dio: dioWith(s.adapter, base: base),
  username: 'test-user',
  password: 'test-password',
  parseRunner: _inline,
);

void main() {
  group('session id handshake', () {
    test('409 then success: id kept in memory and reused', () async {
      final s = FakeTransmission();
      final c = _client(s);
      expect((await c.fetchVersion()).valueOrNull, '4.0.5');
      expect(s.seen, hasLength(2));
      expect(s.seen.first.headers['X-Transmission-Session-Id'], isNull);
      expect(s.seen.last.headers['X-Transmission-Session-Id'], s.sessionId);
      await c.listTorrents();
      // No new handshake for the second call.
      expect(s.seen, hasLength(3));
    });

    test('two 409 in a row is server_error, never a loop', () async {
      final s = FakeTransmission()..stormRemaining = 50;
      final r = await _client(s).fetchVersion();
      expect(r.errorOrNull?.category, ErrorCategory.serverError);
      expect(s.seen, hasLength(2));
    });

    test('a session id that changes mid-session is picked up once', () async {
      final s = FakeTransmission();
      final c = _client(s);
      await c.listTorrents();
      s.sessionId = 'session-two';
      expect((await c.listTorrents()).isOk, isTrue);
      expect(s.seen.last.headers['X-Transmission-Session-Id'], 'session-two');
    });

    test('forgetSession drops the id', () async {
      final s = FakeTransmission();
      final c = _client(s);
      await c.listTorrents();
      c.forgetSession();
      final before = s.seen.length;
      await c.listTorrents();
      expect(s.seen.length - before, 2);
      expect(s.seen[before].headers['X-Transmission-Session-Id'], isNull);
    });
  });

  group('auth and failures', () {
    test('sends Basic credentials built by the client', () async {
      final s = FakeTransmission();
      s.expectedAuth =
          'Basic ${base64.encode(utf8.encode('test-user:test-password'))}';
      expect((await _client(s).listTorrents()).isOk, isTrue);
    });

    test('401 is auth_failed', () async {
      final s = FakeTransmission()..expectedAuth = 'Basic other';
      expect(
        (await _client(s).listTorrents()).errorOrNull?.category,
        ErrorCategory.authFailed,
      );
    });

    test('malformed JSON is parse_error', () async {
      final c = TransmissionClient(
        dio: dioWith(
          FakeAdapter.fixed('<html>nope</html>'),
          base: 'https://t.example',
        ),
      );
      expect(
        (await c.listTorrents()).errorOrNull?.category,
        ErrorCategory.parseError,
      );
    });

    test('timeout maps to timeout', () async {
      final a = FakeAdapter(
        (o) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: o,
        ),
      );
      final c = TransmissionClient(dio: dioWith(a, base: 'https://t.example'));
      expect(
        (await c.listTorrents()).errorOrNull?.category,
        ErrorCategory.timeout,
      );
    });

    test(
      'a non-success result is server_error without the server text',
      () async {
        final a = FakeAdapter.fixed(
          '{"result":"invalid or corrupt torrent file: secret-passkey"}',
        );
        final r = await TransmissionClient(
          dio: dioWith(a, base: 'https://t.example'),
        ).addMagnetOrUrl('magnet:?xt=urn:btih:${'b' * 40}');
        expect(r.errorOrNull?.category, ErrorCategory.serverError);
        expect(
          '${r.errorOrNull?.debugDetail}',
          isNot(contains('secret-passkey')),
        );
      },
    );

    test('RPC older than 14 is unsupported_version', () async {
      final s = FakeTransmission(rpcVersion: 12);
      expect(
        (await _client(s).fetchVersion()).errorOrNull?.category,
        ErrorCategory.unsupportedVersion,
      );
    });

    test('keeps a reverse-proxy path prefix', () async {
      final s = FakeTransmission();
      await _client(s, base: 'https://t.example/prefix').listTorrents();
      expect(s.seen.first.uri.path, '/prefix/transmission/rpc');
    });
  });

  group('add options and capabilities', () {
    test('labels are sent on RPC 16+, tags capability follows', () async {
      final s = FakeTransmission();
      final c = _client(s);
      await c.addMagnetOrUrl(
        exampleMagnet,
        options: const AddTorrentOptions(tags: ['example']),
      );
      expect(s.lastLabels, ['example']);
      expect(c.capabilities.tags, isTrue);
    });

    test('RPC 14 has no tags and sends no labels', () async {
      final s = FakeTransmission(rpcVersion: 14);
      final c = _client(s);
      await c.addMagnetOrUrl(
        exampleMagnet,
        options: const AddTorrentOptions(tags: ['example']),
      );
      expect(s.lastLabels, isEmpty);
      expect(c.capabilities.tags, isFalse);
    });

    test('the file is sent base64 encoded', () async {
      final s = FakeTransmission();
      await _client(s).addFile(
        utf8.encode('d4:infod4:name3:abcee') as dynamic,
        fileName: 'a.torrent',
      );
      expect(
        base64.decode(s.lastMetainfo!),
        utf8.encode('d4:infod4:name3:abcee'),
      );
    });
  });

  group('parsing', () {
    test('unknown fields ignored, optionals tolerated', () {
      final t = parseTransmissionTorrent({
        'hashString': 'h',
        'name': 'Example',
        'status': 6,
        'futureField': {'x': 1},
      });
      expect(t.state, TorrentState.seeding);
      expect(t.size, 0);
      expect(t.eta, isNull);
    });

    test('wrong types give parse_error through the client', () async {
      final a = FakeAdapter.fixed(
        jsonEncode({
          'result': 'success',
          'arguments': {
            'torrents': [
              {'hashString': 5, 'name': 'x'},
            ],
          },
        }),
      );
      final r = await TransmissionClient(
        dio: dioWith(a, base: 'https://t.example'),
      ).listTorrents();
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
    });

    test('state table covers every native status', () {
      const table = {
        0: TorrentState.paused,
        1: TorrentState.checking,
        2: TorrentState.checking,
        3: TorrentState.queued,
        4: TorrentState.downloading,
        5: TorrentState.queued,
        6: TorrentState.seeding,
        99: TorrentState.unknown,
      };
      table.forEach((raw, expected) {
        expect(TorrentState.fromTransmission(raw, progress: 0.5), expected);
      });
      expect(
        TorrentState.fromTransmission(null, progress: 0),
        TorrentState.unknown,
      );
      expect(
        TorrentState.fromTransmission(0, progress: 1),
        TorrentState.finished,
      );
      expect(
        TorrentState.fromTransmission(6, progress: 1, hasError: true),
        TorrentState.error,
      );
      expect(
        TorrentState.fromTransmission(4, progress: 0.1, receiving: false),
        TorrentState.stalled,
      );
    });

    test('10,000 torrents parse in a real isolate', () async {
      final rows = [
        for (var i = 0; i < 10000; i++)
          {
            'hashString': 'h$i',
            'name': 'Example $i',
            'status': 4,
            'percentDone': 0.5,
          },
      ];
      final body = jsonEncode({
        'result': 'success',
        'arguments': {'torrents': rows},
      });
      final s = FakeAdapter((o) => FakeAdapter.reply(body));
      final c = TransmissionClient(dio: dioWith(s, base: 'https://t.example'));
      final r = await c.listTorrents();
      expect(r.valueOrNull, hasLength(10000));
    });
  });
}
