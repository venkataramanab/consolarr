// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:consolarr/features/servers/application/auth_headers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

ServerProfile profile(
  ServiceKind kind,
  AuthMode mode, [
  List<String> headers = const [],
]) => ServerProfile.parse(
  id: 'p1',
  name: 'n',
  kind: kind,
  address: 'https://host.example',
  authMode: mode,
  headerNames: headers,
).valueOrNull!;

void main() {
  test('api key goes in X-Api-Key, never anywhere else', () {
    final h = buildAuthHeaders(
      profile(ServiceKind.sonarr, AuthMode.apiKey),
      const ServerCredentials(apiKey: 'test-key-0000'),
    );
    expect(h, {'X-Api-Key': 'test-key-0000'});
  });

  test('basic auth for Sonarr is an Authorization header next to the key', () {
    final h = buildAuthHeaders(
      profile(ServiceKind.sonarr, AuthMode.basic),
      const ServerCredentials(
        apiKey: 'test-key-0000',
        username: 'user',
        password: 'pw',
      ),
    );
    expect(
      h['Authorization'],
      'Basic ${base64.encode(utf8.encode('user:pw'))}',
    );
    expect(h['X-Api-Key'], 'test-key-0000');
  });

  test('arr kinds send no auth header at all without an API key', () {
    for (final kind in [ServiceKind.sonarr, ServiceKind.radarr]) {
      for (final mode in AuthMode.values) {
        for (final creds in const [
          ServerCredentials(username: 'user', password: 'pw'),
          ServerCredentials(apiKey: '', username: 'user', password: 'pw'),
          ServerCredentials(apiKey: 'bad\nkey', username: 'u', password: 'p'),
        ]) {
          expect(
            buildAuthHeaders(profile(kind, mode), creds),
            isEmpty,
            reason: '$kind $mode: Basic is only ever additive to a key',
          );
        }
      }
    }
  });

  test('basic auth for qBittorrent adds no header (client logs in)', () {
    final h = buildAuthHeaders(
      profile(ServiceKind.qbittorrent, AuthMode.basic),
      const ServerCredentials(username: 'user', password: 'pw'),
    );
    expect(h, isEmpty);
  });

  test('arr kinds always send X-Api-Key when a key is stored', () {
    for (final kind in [ServiceKind.sonarr, ServiceKind.radarr]) {
      for (final mode in AuthMode.values) {
        expect(
          buildAuthHeaders(
            profile(kind, mode),
            const ServerCredentials(apiKey: 'test-key-0000'),
          ),
          {'X-Api-Key': 'test-key-0000'},
          reason: '$kind $mode',
        );
      }
    }
  });

  test('arr proxy login adds Basic next to the API key, never instead', () {
    final basic = 'Basic ${base64.encode(utf8.encode('user:pw'))}';
    for (final kind in [ServiceKind.sonarr, ServiceKind.radarr]) {
      expect(
        buildAuthHeaders(
          profile(kind, AuthMode.apiKey),
          const ServerCredentials(
            apiKey: 'test-key-0000',
            username: 'user',
            password: 'pw',
          ),
        ),
        {'X-Api-Key': 'test-key-0000', 'Authorization': basic},
      );
    }
  });

  test('an empty or half proxy login adds no Authorization header', () {
    for (final c in const [
      ServerCredentials(apiKey: 'k', username: '', password: ''),
      ServerCredentials(apiKey: 'k', username: 'user'),
      ServerCredentials(apiKey: 'k', password: 'pw'),
    ]) {
      expect(
        buildAuthHeaders(profile(ServiceKind.radarr, AuthMode.apiKey), c),
        {'X-Api-Key': 'k'},
      );
    }
  });

  test('torrent kinds still add no credential header in any mode', () {
    for (final mode in AuthMode.values) {
      expect(
        buildAuthHeaders(
          profile(ServiceKind.deluge, mode),
          const ServerCredentials(
            apiKey: 'k',
            username: 'user',
            password: 'pw',
          ),
        ),
        isEmpty,
      );
    }
  });

  test('missing secrets add nothing', () {
    expect(
      buildAuthHeaders(
        profile(ServiceKind.sonarr, AuthMode.apiKey),
        ServerCredentials.empty,
      ),
      isEmpty,
    );
  });

  test(
    'custom headers use profile names and secret values; bad values skipped',
    () {
      final h = buildAuthHeaders(
        profile(ServiceKind.sonarr, AuthMode.none, ['X-A', 'X-B']),
        const ServerCredentials(
          headers: [
            HeaderEntry(name: 'X-A', value: 'one'),
            HeaderEntry(name: 'X-B', value: 'bad\r\nInjected: 1'),
            HeaderEntry(name: 'X-Unlisted', value: 'nope'),
          ],
        ),
      );
      expect(h, {'X-A': 'one'});
    },
  );
}
