// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

Future<T> _inline<T>(T Function() work) async => work();

DelugeClient _client(
  FakeDeluge s, {
  String password = 'test-password',
  String? hostId,
  void Function(String)? onHost,
}) => DelugeClient(
  dio: dioWith(s.adapter, base: 'https://deluge.example'),
  password: password,
  hostId: hostId,
  parseRunner: _inline,
  onHostConnected: onHost,
);

void main() {
  group('login', () {
    test('ok: cookie is sent afterwards, one login', () async {
      final s = FakeDeluge();
      final c = _client(s);
      expect((await c.fetchVersion()).valueOrNull, '2.1.1');
      await c.listTorrents();
      expect(s.logins, 1);
    });

    test('wrong password is auth_failed', () async {
      final s = FakeDeluge();
      final r = await _client(s, password: 'nope').fetchVersion();
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
    });

    test('no password is auth_failed without a request', () async {
      final s = FakeDeluge();
      final r = await DelugeClient(dio: dioWith(s.adapter)).fetchVersion();
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
      expect(s.adapter.requests, isEmpty);
    });

    test('expired cookie: re-login once and the call succeeds', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      s.expireSession();
      expect((await c.listTorrents()).isOk, isTrue);
      expect(s.logins, 2);
    });

    test('expired cookie on a small call re-logs in once', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.transferInfo();
      s.expireSession();
      expect((await c.transferInfo()).isOk, isTrue);
      expect(s.logins, 2);
    });

    test('the session cookie never appears in a URL', () async {
      final s = FakeDeluge();
      await _client(s).listTorrents();
      for (final r in s.adapter.requests) {
        expect(r.uri.toString(), isNot(contains('sid-')));
        expect(r.uri.query, isEmpty);
      }
    });
  });

  group('daemon connection', () {
    test('not connected, one host: connects by itself', () async {
      final s = FakeDeluge(connected: false);
      String? remembered;
      final c = _client(s, onHost: (id) => remembered = id);
      expect((await c.listTorrents()).isOk, isTrue);
      expect(s.connectedTo, 'host1');
      expect(remembered, 'host1');
    });

    test('several hosts: asks for a choice, then connects to it', () async {
      final s = FakeDeluge(
        connected: false,
        hosts: [
          ['h1', 'a.example', 58846, 'Online'],
          ['h2', 'b.example', 58846, 'Online'],
        ],
      );
      final c = _client(s);
      final r = await c.listTorrents();
      final err = r.errorOrNull;
      expect(err, isA<DelugeHostRequired>());
      expect((err! as DelugeHostRequired).hosts.map((h) => h.id), ['h1', 'h2']);
      expect((await c.selectHost('h2')).isOk, isTrue);
      expect(s.connectedTo, 'h2');
      expect((await c.listTorrents()).isOk, isTrue);
    });

    test('a remembered host id is used without asking', () async {
      final s = FakeDeluge(
        connected: false,
        hosts: [
          ['h1', 'a.example', 58846, 'Online'],
          ['h2', 'b.example', 58846, 'Online'],
        ],
      );
      expect((await _client(s, hostId: 'h2').listTorrents()).isOk, isTrue);
      expect(s.connectedTo, 'h2');
    });

    test('no hosts at all is not_found', () async {
      final s = FakeDeluge(connected: false, hosts: const []);
      final r = await _client(s).listTorrents();
      expect(r.errorOrNull?.category, ErrorCategory.notFound);
      expect(r.errorOrNull, isNot(isA<DelugeHostRequired>()));
    });
  });

  group('labels', () {
    test('plugin present: label model and label applied on add', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      expect(c.capabilities.labelModel, LabelModel.label);
      expect(c.capabilities.labelsNeedPlugin, isFalse);
      await c.addMagnetOrUrl(
        exampleMagnet,
        options: const AddTorrentOptions(category: 'example'),
      );
      expect(s.labels, ['example']);
      expect(s.lastLabel, 'example');
    });

    test('plugin absent: no label model, label ignored', () async {
      final s = FakeDeluge(labelPlugin: false);
      final c = _client(s);
      await c.listTorrents();
      expect(c.capabilities.labelModel, LabelModel.none);
      expect(c.capabilities.labelsNeedPlugin, isTrue);
      await c.addMagnetOrUrl(
        exampleMagnet,
        options: const AddTorrentOptions(category: 'example'),
      );
      expect(s.methods, isNot(contains('label.add')));
    });
  });

  group('add file', () {
    test('uploads first, then adds the uploaded path', () async {
      final s = FakeDeluge();
      final c = _client(s);
      final r = await c.addFile(
        utf8.encode('d4:infod4:name3:abcee') as dynamic,
        fileName: 'a.torrent',
      );
      expect(r.isOk, isTrue);
      expect(s.uploads, 1);
      expect(s.methods.last, 'web.add_torrents');
    });
  });

  group('parsing', () {
    test('state table covers every native state', () {
      const table = {
        'Downloading': TorrentState.downloading,
        'Seeding': TorrentState.seeding,
        'Queued': TorrentState.queued,
        'Checking': TorrentState.checking,
        'Allocating': TorrentState.checking,
        'Moving': TorrentState.checking,
        'Error': TorrentState.error,
        'Paused': TorrentState.paused,
        'Whatever': TorrentState.unknown,
      };
      table.forEach((raw, expected) {
        expect(TorrentState.fromDeluge(raw, progress: 0.5), expected);
      });
      expect(
        TorrentState.fromDeluge('Paused', progress: 1),
        TorrentState.finished,
      );
      expect(TorrentState.fromDeluge(null, progress: 0), TorrentState.unknown);
    });

    test('unknown fields ignored, missing optionals tolerated', () {
      final t = parseDelugeTorrent('h', {
        'name': 'Example',
        'state': 'Seeding',
        'x': 1,
      });
      expect(t.state, TorrentState.seeding);
      expect(t.size, 0);
      expect(t.category, isNull);
    });

    test('wrong types give parse_error', () async {
      final a = FakeAdapter((o) {
        final method = (jsonDecode(o.data as String) as Map)['method'];
        if (method == 'auth.login') {
          return FakeAdapter.reply(
            '{"result":true,"error":null,"id":1}',
            headers: {
              'set-cookie': ['_session_id=x; Path=/'],
            },
          );
        }
        if (method == 'web.connected') {
          return FakeAdapter.reply('{"result":true,"error":null,"id":1}');
        }
        if (method == 'core.get_enabled_plugins') {
          return FakeAdapter.reply('{"result":[],"error":null,"id":1}');
        }
        return FakeAdapter.reply(
          '{"result":{"h":{"name":5}},"error":null,"id":1}',
        );
      });
      final r = await DelugeClient(
        dio: dioWith(a, base: 'https://deluge.example'),
        password: 'test-password',
      ).listTorrents();
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
    });

    test('10,000 torrents parse in a real isolate', () async {
      final rows = {
        for (var i = 0; i < 10000; i++)
          'h$i': {
            'name': 'Example $i',
            'state': 'Downloading',
            'progress': 50.0,
          },
      };
      final body = jsonEncode({'result': rows, 'error': null, 'id': 1});
      final r = parseDelugeListResponse(body);
      expect(r.rows!.items, hasLength(10000));
      final s = FakeDeluge();
      // Large payloads go through the (real) runner.
      final big = DelugeClient(
        dio: dioWith(
          FakeAdapter((o) {
            final m = (jsonDecode(o.data as String) as Map)['method'];
            if (m == 'core.get_torrents_status') return FakeAdapter.reply(body);
            return s.adapter.handler(o);
          }),
          base: 'https://deluge.example',
        ),
        password: 'test-password',
      );
      expect((await big.listTorrents()).valueOrNull, hasLength(10000));
    });
  });
}
