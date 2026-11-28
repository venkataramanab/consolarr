// SPDX-License-Identifier: GPL-3.0-or-later

// A login or session handshake answered by another origin (after a redirect)
// must not plant a session. Uses the real secure adapter against local
// servers: one is the configured server, the other is "elsewhere".

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

typedef _Handler = FutureOr<void> Function(HttpRequest request);

class _Local {
  _Local(this.server, this.log);

  final HttpServer server;

  /// `METHOD path` plus whether a Cookie or session-id header came along.
  final List<String> log;

  String get origin => 'http://127.0.0.1:${server.port}';

  static Future<_Local> start(_Handler handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final log = <String>[];
    server.listen((request) async {
      final marks = [
        if (request.headers.value('cookie') != null) 'cookie',
        if (request.headers.value('x-transmission-session-id') != null) 'sid',
      ];
      log.add('${request.method} ${request.uri.path} ${marks.join(',')}');
      await handler(request);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    return _Local(server, log);
  }
}

Dio _dio(String origin) => _factory().create(
  ServerProfile.parse(
    id: 'p',
    name: 'n',
    kind: ServiceKind.qbittorrent,
    address: origin,
    allowCleartext: true,
  ).valueOrNull!,
);

DefaultSecureHttpClientFactory _factory() =>
    DefaultSecureHttpClientFactory(pins: InMemoryPinStore());

void _redirect(HttpRequest r, String to) {
  r.response
    ..statusCode = 302
    ..headers.set('location', to);
}

void main() {
  group('qBittorrent', () {
    test('a login redirected to another origin sets no session', () async {
      final other = await _Local.start((r) {
        r.response
          ..headers.add('set-cookie', 'SID=${'e' * 8}; path=/')
          ..write('Ok.');
      });
      final home = await _Local.start((r) {
        _redirect(r, '${other.origin}/api/v2/auth/login');
      });
      final client = QBittorrentClient(
        dio: _dio(home.origin),
        username: 'u',
        password: 'p',
      );
      final result = await client.fetchVersion();
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.category, ErrorCategory.redirectRefused);
      expect(home.log.length, 1);
      // No second request carried a planted cookie anywhere.
      expect(other.log.where((l) => l.endsWith('cookie')), isEmpty);
    });

    test('a same-origin redirect still logs in', () async {
      late _Local home;
      home = await _Local.start((r) {
        final path = r.uri.path;
        if (path.endsWith('/auth/login')) {
          _redirect(r, '${home.origin}/api/v2/auth/login2');
        } else if (path.endsWith('/auth/login2')) {
          r.response
            ..headers.add('set-cookie', 'SID=${'a' * 8}; path=/')
            ..write('Ok.');
        } else if (r.headers.value('cookie') == null) {
          r.response.statusCode = 403;
        } else {
          r.response.write('v5.0.0');
        }
      });
      final client = QBittorrentClient(
        dio: _dio(home.origin),
        username: 'u',
        password: 'p',
      );
      final result = await client.fetchVersion();
      expect(result.valueOrNull, 'v5.0.0');
      expect(home.log.last, endsWith('cookie'));
    });
  });

  group('Deluge', () {
    String rpc(Object? result) =>
        jsonEncode({'id': 1, 'result': result, 'error': null});

    test('a login redirected to another origin sets no session', () async {
      final other = await _Local.start((r) {
        r.response
          ..headers.add('set-cookie', '_session_id=${'e' * 8}; path=/')
          ..write(rpc(true));
      });
      final home = await _Local.start((r) {
        _redirect(r, '${other.origin}/json');
      });
      final client = DelugeClient(dio: _dio(home.origin), password: 'p');
      final result = await client.fetchVersion();
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.category, ErrorCategory.authFailed);
      expect(other.log.where((l) => l.endsWith('cookie')), isEmpty);
    });

    test('a same-origin redirect still logs in', () async {
      late _Local home;
      home = await _Local.start((r) async {
        final body = await utf8.decoder.bind(r).join();
        if (r.method == 'POST' && body.contains('auth.login')) {
          _redirect(r, '${home.origin}/json2');
        } else if (r.uri.path == '/json2') {
          r.response
            ..headers.add('set-cookie', '_session_id=${'a' * 8}; path=/')
            ..write(rpc(true));
        } else {
          r.response.write(rpc(true));
        }
      });
      final client = DelugeClient(dio: _dio(home.origin), password: 'p');
      await client.fetchVersion();
      expect(
        home.log.where(
          (l) => l.startsWith('POST /json ') && l.endsWith('cookie'),
        ),
        isNotEmpty,
        reason: 'the session cookie from the same-origin redirect is used',
      );
    });
  });

  group('Transmission', () {
    test('a session id from another origin is refused', () async {
      final other = await _Local.start((r) {
        r.response
          ..statusCode = 409
          ..headers.set('x-transmission-session-id', 'x' * 12);
      });
      final home = await _Local.start((r) {
        _redirect(r, '${other.origin}/transmission/rpc');
      });
      final client = TransmissionClient(dio: _dio(home.origin));
      final result = await client.fetchVersion();
      expect(result.isErr, isTrue);
      expect(result.errorOrNull!.category, ErrorCategory.redirectRefused);
      expect(other.log.where((l) => l.endsWith('sid')), isEmpty);
    });

    test('a same-origin redirect still yields the session id', () async {
      late _Local home;
      home = await _Local.start((r) {
        if (r.uri.path == '/transmission/rpc' && r.method == 'POST') {
          if (r.headers.value('x-transmission-session-id') == null) {
            _redirect(r, '${home.origin}/transmission/rpc2');
          } else {
            r.response.write(
              jsonEncode({
                'result': 'success',
                'arguments': {'version': '4.0.0 (x)', 'rpc-version': 17},
              }),
            );
          }
        } else {
          r.response
            ..statusCode = 409
            ..headers.set('x-transmission-session-id', 'y' * 12);
        }
      });
      final client = TransmissionClient(dio: _dio(home.origin));
      final result = await client.fetchVersion();
      expect(result.valueOrNull, '4.0.0');
    });
  });
}
