// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

Future<T> _inline<T>(T Function() work) async => work();

DelugeClient _client(FakeDeluge s) => DelugeClient(
  dio: dioWith(s.adapter, base: 'https://deluge.example'),
  password: 'test-password',
  parseRunner: _inline,
);

Future<void> _addExtra(FakeDeluge s, int n) async {
  for (var i = 0; i < n; i++) {
    s.torrents.add(FakeTorrent(i.toRadixString(16).padLeft(40, 'd'), 'Row $i'));
  }
}

void main() {
  group('magnet scheme', () {
    test('is case-insensitive', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.addMagnetOrUrl('MAGNET:?xt=urn:btih:${'b' * 40}');
      expect(s.methods, contains('core.add_torrent_magnet'));
      expect(s.methods, isNot(contains('core.add_torrent_url')));
    });
  });

  group('session cookie origin', () {
    test('a cookie from another origin is not kept', () async {
      var first = true;
      final a = FakeAdapter((o) {
        final body = jsonEncode({'result': true, 'error': null, 'id': 1});
        if (first) {
          first = false;
          return ResponseBody.fromString(
              body,
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
                'set-cookie': ['_session_id=stolen; Path=/'],
              },
            )
            ..redirects = [
              RedirectRecord(
                302,
                'POST',
                Uri.parse('https://evil.example/json'),
              ),
            ];
        }
        return FakeAdapter.reply(body);
      });
      final c = DelugeClient(
        dio: dioWith(a, base: 'https://deluge.example'),
        password: 'test-password',
      );
      final r = await c.fetchVersion();
      // The login is refused: no usable cookie came from our origin.
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
    });

    test('the same origin (default port spelled out) is accepted', () async {
      final s = FakeDeluge();
      final c = DelugeClient(
        dio: dioWith(s.adapter, base: 'https://deluge.example:443'),
        password: 'test-password',
        parseRunner: _inline,
      );
      expect((await c.listTorrents()).isOk, isTrue);
    });
  });

  group('daemon drops', () {
    test('list reconnects and retries once', () async {
      final s = FakeDeluge();
      final c = _client(s);
      expect((await c.listTorrents()).isOk, isTrue);
      s.dropDaemon();
      final r = await c.listTorrents();
      expect(r.isOk, isTrue, reason: '${r.errorOrNull?.category}');
      expect(s.connectedTo, 'host1');
    });

    test('an action reconnects and retries once', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      s.dropDaemon();
      final r = await c.pause([exampleHash]);
      expect(r.isOk, isTrue, reason: '${r.errorOrNull?.category}');
      expect(s.torrents.single.paused, isTrue);
    });

    test('a daemon that stays away is network_unreachable', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      s.dropDaemon();
      // The web UI claims to be connected but the daemon keeps refusing.
      final stuck = FakeAdapter((o) {
        final req = jsonDecode(o.data as String) as Map<String, Object?>;
        final method = req['method']! as String;
        Object? result = true;
        Object? error;
        if (method.startsWith('core.')) {
          result = null;
          error = {'message': 'Not connected.', 'code': 4};
        }
        return FakeAdapter.reply(
          jsonEncode({'result': result, 'error': error, 'id': req['id']}),
          headers: {
            'set-cookie': ['_session_id=x; Path=/'],
          },
        );
      });
      final c2 = DelugeClient(
        dio: dioWith(stuck, base: 'https://deluge.example'),
        password: 'test-password',
        parseRunner: _inline,
      );
      final r = await c2.listTorrents();
      expect(r.errorOrNull?.category, ErrorCategory.networkUnreachable);
    });
  });

  group('labels', () {
    test('uppercase is lowercased and applied', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      final warnings = <AddWarning>[];
      final r = await c.addMagnetOrUrl(
        exampleMagnet,
        options: AddTorrentOptions(category: 'Movies', onWarning: warnings.add),
      );
      expect(r.isOk, isTrue);
      expect(s.labels, ['movies']);
      expect(warnings, isEmpty);
    });

    test('an unusable label does not fail the add: warning only', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      final warnings = <AddWarning>[];
      final r = await c.addMagnetOrUrl(
        exampleMagnet,
        options: AddTorrentOptions(
          category: 'my movies',
          onWarning: warnings.add,
        ),
      );
      expect(r.isOk, isTrue);
      expect(s.addCalls, 1);
      expect(warnings, [AddWarning.labelNotApplied]);
    });

    test('addFile labels the new torrent, not the last row', () async {
      final s = FakeDeluge()
        ..addPrepends = true
        ..addedHash = 'e' * 40;
      await _addExtra(s, 3);
      final c = _client(s);
      await c.listTorrents();
      final r = await c.addFile(
        Uint8List.fromList(utf8.encode('d4:infod4:name3:abcee')),
        fileName: 'a.torrent',
        options: const AddTorrentOptions(category: 'example'),
      );
      expect(r.isOk, isTrue);
      expect(s.labelled, ['e' * 40]);
    });

    test('T2: a failed before-snapshot reports the label as not applied, '
        'the add still succeeds', () async {
      final s = FakeDeluge();
      final c = _client(s);
      await c.listTorrents();
      // The snapshot taken before the upload fails once (a transport error).
      s.timeouts['core.get_torrents_status'] = 1;
      final warnings = <AddWarning>[];
      final r = await c.addFile(
        Uint8List.fromList(utf8.encode('d4:infod4:name3:abcee')),
        fileName: 'a.torrent',
        options: AddTorrentOptions(
          category: 'example',
          onWarning: warnings.add,
        ),
      );
      expect(r.isOk, isTrue);
      expect(s.uploads, 1);
      expect(s.labelled, isEmpty);
      expect(warnings, [AddWarning.labelNotApplied]);
    });

    test(
      'T7: a timeout while labelling is a warning, not an add error',
      () async {
        for (final method in ['label.get_labels', 'label.set_torrent']) {
          final s = FakeDeluge();
          final c = _client(s);
          await c.listTorrents();
          s.timeouts[method] = -1;
          final warnings = <AddWarning>[];
          final r = await c.addMagnetOrUrl(
            exampleMagnet,
            options: AddTorrentOptions(
              category: 'example',
              onWarning: warnings.add,
            ),
          );
          expect(r.isOk, isTrue, reason: method);
          expect(s.addCalls, 1, reason: method);
          expect(warnings, [AddWarning.labelNotApplied], reason: method);
        }
      },
    );

    test(
      'T7: the same for a file add (the new torrent cannot be labelled)',
      () async {
        final s = FakeDeluge();
        final c = _client(s);
        await c.listTorrents();
        s.timeouts['label.set_torrent'] = -1;
        final warnings = <AddWarning>[];
        final r = await c.addFile(
          Uint8List.fromList(utf8.encode('d4:infod4:name3:abcee')),
          fileName: 'b.torrent',
          options: AddTorrentOptions(
            category: 'example',
            onWarning: warnings.add,
          ),
        );
        expect(r.isOk, isTrue);
        expect(s.uploads, 1);
        expect(warnings, [AddWarning.labelNotApplied]);
      },
    );

    test('valid label names', () {
      expect(isValidDelugeLabel('example'), isTrue);
      expect(isValidDelugeLabel('tv_shows-2.1'), isTrue);
      expect(isValidDelugeLabel('Example'), isTrue);
      expect(isValidDelugeLabel('my movies'), isFalse);
      expect(isValidDelugeLabel('ünï'), isFalse);
      expect(isValidDelugeLabel(''), isFalse);
    });
  });

  group('partial failures', () {
    test(
      'delete continues past a failure and reports the failed ids',
      () async {
        final s = FakeDeluge();
        await _addExtra(s, 3);
        final ids = s.torrents.map((t) => t.hash).toList();
        s.failRemove.add(ids[1]);
        final c = _client(s);
        final r = await c.delete(ids, deleteFiles: false);
        final e = r.errorOrNull;
        expect(e, isA<PartialActionFailure>());
        final p = e! as PartialActionFailure;
        expect(p.failed, [ids[1]]);
        expect(p.total, 4);
        expect(s.torrents.map((t) => t.hash), [ids[1]]);
      },
    );

    test('delete where every id fails is a plain error', () async {
      final s = FakeDeluge();
      s.failRemove.add(exampleHash);
      final r = await _client(s).delete([exampleHash], deleteFiles: false);
      expect(r.errorOrNull, isNot(isA<PartialActionFailure>()));
      expect(r.errorOrNull?.category, ErrorCategory.serverError);
    });

    test('pause: per-id failures from Deluge 2.x are reported', () async {
      final s = FakeDeluge();
      await _addExtra(s, 2);
      final ids = s.torrents.map((t) => t.hash).toList();
      s.failPause.add(ids[2]);
      final r = await _client(s).pause(ids);
      final p = r.errorOrNull! as PartialActionFailure;
      expect(p.failed, [ids[2]]);
      expect(p.total, 3);
      expect(s.torrents.where((t) => t.paused), hasLength(2));
    });

    test('everything ok stays ok', () async {
      final s = FakeDeluge();
      expect((await _client(s).pause([exampleHash])).isOk, isTrue);
    });
  });
}
