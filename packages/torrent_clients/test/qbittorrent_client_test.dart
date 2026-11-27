// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'models_test.dart' show fullTorrent;
import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

Future<T> _inline<T>(T Function() work) async => work();

const _cookie = 'SID=test-session-0000';

ResponseBody _loginOk() => FakeAdapter.reply(
  'Ok.',
  headers: {
    'set-cookie': ['$_cookie; HttpOnly; SameSite=Strict; path=/'],
  },
);

/// A fake qBittorrent: login + data endpoints, optionally demanding a cookie.
FakeAdapter _server({
  String password = 'test-password',
  bool Function()? sessionExpired,
  Map<String, String> data = const {},
  bool banned = false,
}) {
  return FakeAdapter((o) {
    final path = o.uri.path;
    if (path.endsWith('/auth/login')) {
      if (banned) return FakeAdapter.reply('Forbidden', status: 403);
      final form = '${o.data}';
      return form.contains('password=$password')
          ? _loginOk()
          : FakeAdapter.reply('Fails.');
    }
    final hasCookie = '${o.headers['Cookie']}'.contains(_cookie);
    if (!hasCookie || (sessionExpired?.call() ?? false)) {
      return FakeAdapter.reply('Forbidden', status: 403);
    }
    final key = path.split('/api/v2/').last;
    return FakeAdapter.reply(data[key] ?? '{}');
  });
}

QBittorrentClient _client(
  FakeAdapter a, {
  String? user = 'test-user',
  String? pass = 'test-password',
  String base = 'https://qbit.example',
}) => QBittorrentClient(
  dio: dioWith(a, base: base),
  username: user,
  password: pass,
  parseRunner: _inline,
);

void main() {
  qbittorrentActionTests();
  group('login and session', () {
    test('logs in once, then sends the cookie, Referer and Origin', () async {
      final a = _server(data: {'app/version': 'v4.6.3'});
      final c = _client(a);
      expect((await c.fetchVersion()).valueOrNull, 'v4.6.3');
      expect((await c.fetchVersion()).valueOrNull, 'v4.6.3');
      final logins = a.requests.where((r) => r.path.endsWith('/auth/login'));
      expect(logins, hasLength(1));
      final data = a.requests.last;
      expect(data.headers['Cookie'], contains(_cookie));
      expect(data.headers['Referer'], 'https://qbit.example');
      expect(data.headers['Origin'], 'https://qbit.example');
    });

    test(
      'login posts a form body and keeps credentials out of the URL',
      () async {
        final a = _server(data: {'app/version': 'v4.6.3'});
        await _client(a).fetchVersion();
        final login = a.requests.first;
        expect(login.method, 'POST');
        expect(login.uri.query, isEmpty);
        expect(login.uri.toString(), isNot(contains('test-')));
        expect('${login.data}', contains('username=test-user'));
      },
    );

    test('wrong password (Fails.) is auth_failed', () async {
      final r = await _client(_server(), pass: 'nope').fetchVersion();
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
      expect(r.errorOrNull?.debugDetail, isNot('banned'));
    });

    test('banned IP (403 on login) is auth_failed / banned', () async {
      final r = await _client(_server(banned: true)).fetchVersion();
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
      expect(r.errorOrNull?.debugDetail, 'banned');
    });

    test('expired session triggers exactly one re-login and retry', () async {
      var expireNext = true;
      final a = _server(
        data: {'torrents/info': '[]'},
        sessionExpired: () {
          final e = expireNext;
          expireNext = false;
          return e;
        },
      );
      final c = _client(a);
      expect((await c.listTorrents()).isOk, isTrue);
      final logins = a.requests.where((r) => r.path.endsWith('/auth/login'));
      expect(logins, hasLength(2));
    });

    test('persistent 403 after re-login is auth_failed, not a loop', () async {
      final a = _server(sessionExpired: () => true);
      final r = await _client(a).listTorrents();
      expect(r.errorOrNull?.category, ErrorCategory.authFailed);
      expect(a.requests.length, lessThanOrEqualTo(5));
    });

    test('without credentials no login is attempted', () async {
      final a = FakeAdapter.fixed('v4.6.3');
      final r = await _client(a, user: null, pass: null).fetchVersion();
      expect(r.valueOrNull, 'v4.6.3');
      expect(a.requests.single.path, endsWith('/api/v2/app/version'));
      expect(a.requests.single.headers.containsKey('Cookie'), isFalse);
    });

    test(
      'forgetSession drops the cookie so the next call logs in again',
      () async {
        final a = _server(data: {'app/version': 'v4.6.3'});
        final c = _client(a);
        await c.fetchVersion();
        c.forgetSession();
        await c.fetchVersion();
        expect(
          a.requests.where((r) => r.path.endsWith('/auth/login')),
          hasLength(2),
        );
      },
    );

    test('the cookie is never present in errors', () async {
      final a = _server(sessionExpired: () => true);
      final r = await _client(a).listTorrents();
      expect(
        '${r.errorOrNull} ${r.errorOrNull?.debugDetail}',
        isNot(contains('test-session')),
      );
    });
  });

  group('version', () {
    test('keeps a path prefix', () async {
      final a = _server(data: {'app/version': 'v4.6.3'});
      await _client(a, base: 'https://qbit.example/qbt').fetchVersion();
      expect(a.requests.last.uri.path, '/qbt/api/v2/app/version');
    });

    test('below 4.1 is unsupported_version; 4.1+ and 5.x pass', () async {
      for (final (v, ok) in [
        ('v4.0.4', false),
        ('v3.3.16', false),
        ('v4.1.0', true),
        ('v5.0.1', true),
        ('4.6.3', true),
        ('weird', true),
      ]) {
        final r = await _client(_server(data: {'app/version': v}))
            .fetchVersion();
        expect(r.isOk, ok, reason: v);
        if (!ok) {
          expect(r.errorOrNull?.category, ErrorCategory.unsupportedVersion);
        }
      }
    });

    test('404 is not_found (wrong prefix)', () async {
      final a = FakeAdapter.fixed('', status: 404);
      expect(
        (await _client(
          a,
          user: null,
          pass: null,
        ).fetchVersion()).errorOrNull?.category,
        ErrorCategory.notFound,
      );
    });
  });

  group('lists', () {
    test(
      'malformed rows are skipped and only their count is reported',
      () async {
        final skipped = <int>[];
        final a = _server(
          data: {
            'torrents/info': jsonEncode([fullTorrent(), 5, fullTorrent(2)]),
          },
        );
        final c = QBittorrentClient(
          dio: dioWith(a, base: 'https://qbit.example'),
          username: 'test-user',
          password: 'test-password',
          onRowsSkipped: skipped.add,
        );
        expect((await c.listTorrents()).valueOrNull, hasLength(2));
        expect(skipped, [1]);
      },
    );

    test('torrents/info', () async {
      final a = _server(
        data: {
          'torrents/info': jsonEncode([fullTorrent(), fullTorrent(2)]),
        },
      );
      final r = await _client(a).listTorrents();
      expect(r.valueOrNull, hasLength(2));
      expect(a.requests.last.uri.path, '/api/v2/torrents/info');
    });

    test('transfer/info', () async {
      final a = _server(
        data: {
          'transfer/info': jsonEncode({'dl_info_speed': 7, 'up_info_speed': 3}),
        },
      );
      final r = await _client(a).transferInfo();
      expect(r.valueOrNull?.dlSpeed, 7);
      expect(r.valueOrNull?.upSpeed, 3);
    });

    test('wrong shapes are parse_error', () async {
      final a = _server(
        data: {'torrents/info': '{"a":1}', 'transfer/info': '[]'},
      );
      final c = _client(a);
      expect(
        (await c.listTorrents()).errorOrNull?.category,
        ErrorCategory.parseError,
      );
      expect(
        (await c.transferInfo()).errorOrNull?.category,
        ErrorCategory.parseError,
      );
    });

    test(
      'large lists go through the runner; 10,000 parse in a real isolate',
      () async {
        final big = jsonEncode([
          for (var i = 0; i < 10000; i++)
            {
              'hash': '$i',
              'name': 'Example Torrent $i',
              'state': 'pausedUP',
              'progress': 1,
            },
        ]);
        var calls = 0;
        Future<T> counting<T>(T Function() w) async {
          calls++;
          return w();
        }

        final viaRunner = QBittorrentClient(
          dio: dioWith(_server(data: {'torrents/info': big})),
          username: 'test-user',
          password: 'test-password',
          parseRunner: counting,
        );
        expect((await viaRunner.listTorrents()).valueOrNull, hasLength(10000));
        expect(calls, 1);

        final real = QBittorrentClient(
          dio: dioWith(_server(data: {'torrents/info': big})),
          username: 'test-user',
          password: 'test-password',
        );
        final r = await real.listTorrents();
        expect(r.valueOrNull, hasLength(10000));
        expect(r.valueOrNull!.first.state, TorrentState.finished);
      },
    );
  });

  group('network scenarios', () {
    test('timeout -> timeout', () async {
      final a = FakeAdapter(
        (o) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: o,
        ),
      );
      expect(
        (await _client(a).listTorrents()).errorOrNull?.category,
        ErrorCategory.timeout,
      );
    });

    test('drop mid-body -> network_unreachable', () async {
      final a = FakeAdapter((o) {
        if (o.path.endsWith('/auth/login')) return _loginOk();
        return FakeAdapter.dropped('[{"hash":');
      });
      expect(
        (await _client(a).listTorrents()).errorOrNull?.category,
        ErrorCategory.networkUnreachable,
      );
    });

    test('5xx -> server_error; malformed -> parse_error', () async {
      final a = FakeAdapter((o) {
        if (o.path.endsWith('/auth/login')) return _loginOk();
        return FakeAdapter.reply('', status: 502);
      });
      expect(
        (await _client(a).listTorrents()).errorOrNull?.category,
        ErrorCategory.serverError,
      );
      final b = _server(data: {'torrents/info': '[{"hash":'});
      expect(
        (await _client(b).listTorrents()).errorOrNull?.category,
        ErrorCategory.parseError,
      );
    });

    test('typed secure-client errors pass through', () async {
      final a = FakeAdapter(
        (o) => throw DioException(
          requestOptions: o,
          error: const AppError(ErrorCategory.tlsPinMismatch),
        ),
      );
      expect(
        (await _client(a).listTorrents()).errorOrNull?.category,
        ErrorCategory.tlsPinMismatch,
      );
    });
  });
}

void qbittorrentActionTests() {
  group('actions: version dependent names', () {
    test('v4 uses pause/resume', () async {
      final s = FakeQBittorrent(version: 'v4.6.3');
      final c = QBittorrentClient(
        dio: dioWith(s.adapter),
        username: 'test-user',
        password: 'test-password',
      );
      await c.pause([exampleHash]);
      await c.resume([exampleHash]);
      expect(
        s.paths,
        containsAllInOrder(['torrents/pause', 'torrents/resume']),
      );
      expect(s.paths, isNot(contains('torrents/stop')));
    });

    test('v5 uses stop/start', () async {
      final s = FakeQBittorrent(version: 'v5.0.1');
      final c = QBittorrentClient(
        dio: dioWith(s.adapter),
        username: 'test-user',
        password: 'test-password',
      );
      await c.pause([exampleHash]);
      await c.resume([exampleHash]);
      expect(s.paths, containsAllInOrder(['torrents/stop', 'torrents/start']));
      expect(c.capabilities.distinctStop, isTrue);
    });

    test('a 404 on the chosen name falls back to the other one', () async {
      // The server says v5 but only knows the v4 names.
      final inner = FakeQBittorrent(version: 'v4.6.3');
      final a = FakeAdapter((o) {
        if (o.uri.path.endsWith('app/version'))
          return FakeAdapter.reply('v5.0.0');
        return inner.adapter.handler(o);
      });
      final c = QBittorrentClient(
        dio: dioWith(a),
        username: 'test-user',
        password: 'test-password',
      );
      expect((await c.pause([exampleHash])).isOk, isTrue);
      expect(inner.torrents.single.paused, isTrue);
    });
  });
}
