// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:consolarr/features/servers/application/auth_headers.dart';
import 'package:consolarr/features/servers/application/connection_tester.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';

import '../servers/ui/support.dart' as ui;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async => handler(o);
  @override
  void close({bool force = false}) {}
}

class _Factory implements SecureHttpClientFactory {
  _Factory(this.adapter);
  final HttpClientAdapter adapter;
  @override
  Dio create(ServerProfile profile) =>
      Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
        ..httpClientAdapter = adapter;
}

ResponseBody _json(
  Object body, {
  int status = 200,
  Map<String, List<String>>? h,
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...?h,
  },
);

void main() {
  test('every torrent kind is registered everywhere it must be', () {
    for (final k in [
      ServiceKind.qbittorrent,
      ServiceKind.transmission,
      ServiceKind.deluge,
    ]) {
      expect(torrentClientFactories, contains(k));
      expect(connectionProbes, contains(k));
      expect(supportedServiceKinds, contains(k));
      expect(authHeaderBuilders, contains(k));
    }
    expect(torrentClientFactories.keys.first, ServiceKind.qbittorrent);
  });

  test('torrent kinds offer basic and none; the picker describes them', () {
    for (final k in [ServiceKind.transmission, ServiceKind.deluge]) {
      expect(authModesFor(k), [AuthMode.basic, AuthMode.none]);
    }
  });

  group('connection test (SRV-05)', () {
    ServerProfile p(ServiceKind kind) => ui.profile(
      'x',
      kind: kind,
      address: 'https://x.example',
      authMode: AuthMode.basic,
    );

    test(
      'Transmission: success with the version, 401 and unsupported',
      () async {
        var rpc = 17;
        var auth = true;
        final adapter = _Adapter((o) {
          if (o.headers['X-Transmission-Session-Id'] != 's') {
            return _json(
              {},
              status: 409,
              h: {
                'x-transmission-session-id': ['s'],
              },
            );
          }
          if (!auth) return _json({}, status: 401);
          return _json({
            'result': 'success',
            'arguments': {'version': '4.0.5 (abc)', 'rpc-version': rpc},
          });
        });
        final tester = DefaultConnectionTester(_Factory(adapter));
        const creds = ServerCredentials(username: 'u', password: 'p');
        var r = await tester.test(p(ServiceKind.transmission), creds);
        expect((r as ConnectionTestSuccess).version, '4.0.5');
        expect(r.majorVersion, 4);
        auth = false;
        r = await tester.test(p(ServiceKind.transmission), creds);
        expect(
          (r as ConnectionTestFailure).error.category,
          ErrorCategory.authFailed,
        );
        auth = true;
        rpc = 10;
        r = await tester.test(p(ServiceKind.transmission), creds);
        expect(
          (r as ConnectionTestFailure).error.category,
          ErrorCategory.unsupportedVersion,
        );
      },
    );

    test('Deluge: success, wrong password, wrong path prefix', () async {
      var good = true;
      final adapter = _Adapter((o) {
        final method = jsonDecode(o.data as String)['method'];
        if (method == 'auth.login') {
          return _json(
            {'result': good, 'error': null, 'id': 1},
            h: good
                ? {
                    'set-cookie': ['_session_id=s; Path=/'],
                  }
                : null,
          );
        }
        return _json({
          'result': method == 'daemon.get_version' ? '2.1.1' : true,
          'error': null,
          'id': 1,
        });
      });
      final tester = DefaultConnectionTester(_Factory(adapter));
      const creds = ServerCredentials(password: 'p');
      var r = await tester.test(p(ServiceKind.deluge), creds);
      expect((r as ConnectionTestSuccess).version, '2.1.1');
      good = false;
      r = await tester.test(p(ServiceKind.deluge), creds);
      expect(
        (r as ConnectionTestFailure).error.category,
        ErrorCategory.authFailed,
      );
      final notFound = DefaultConnectionTester(
        _Factory(_Adapter((o) => _json({}, status: 404))),
      );
      r = await notFound.test(p(ServiceKind.deluge), creds);
      expect(
        (r as ConnectionTestFailure).error.category,
        ErrorCategory.notFound,
      );
    });
  });

  group(
    'Transmission credentials come from the client, not the shared headers',
    () {
      test(
        'the header builder adds nothing; the client sends Basic itself',
        () {
          final profile = ui.profile(
            'x',
            kind: ServiceKind.transmission,
            address: 'https://x.example',
            authMode: AuthMode.basic,
          );
          const creds = ServerCredentials(
            username: 'test-user',
            password: 'test-password',
          );
          expect(buildAuthHeaders(profile, creds), isEmpty);
        },
      );
    },
  );

  group('no header secret reaches a log line', () {
    test('Authorization, Cookie, Set-Cookie and the session id are redacted', () {
      const sessionId = 'session-secret-123';
      final basic =
          'Basic ${base64.encode(utf8.encode('test-user:test-password'))}';
      final lines = [
        'Authorization: $basic',
        'X-Transmission-Session-Id: $sessionId',
        'Cookie: _session_id=cookie-secret-456; SID=qb-secret-789',
        'Set-Cookie: _session_id=cookie-secret-456; Path=/; HttpOnly',
        'headers {Authorization: $basic, X-Transmission-Session-Id: $sessionId}',
      ];
      final out = <String>[];
      final logger = AppLogger(sink: (level, msg) => out.add(msg));
      for (final l in lines) {
        logger.info(l);
      }
      final joined = out.join('\n');
      for (final secret in [
        basic,
        base64.encode(utf8.encode('test-user:test-password')),
        sessionId,
        'cookie-secret-456',
        'qb-secret-789',
      ]) {
        expect(joined, isNot(contains(secret)));
      }
    });
  });

  test('the registry builds each client kind', () {
    for (final entry in torrentClientFactories.entries) {
      final profile = ui.profile(
        'x',
        kind: entry.key,
        address: 'https://x.example',
        authMode: AuthMode.basic,
      );
      final client = entry.value(
        TorrentClientContext(
          dio: Dio(),
          profile: profile,
          credentials: const ServerCredentials(username: 'u', password: 'p'),
          onRowsSkipped: (_) {},
        ),
      );
      expect(client.kind, entry.key);
    }
  });
}
