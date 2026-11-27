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

  test('basic auth for Sonarr is an Authorization header', () {
    final h = buildAuthHeaders(
      profile(ServiceKind.sonarr, AuthMode.basic),
      const ServerCredentials(username: 'user', password: 'pw'),
    );
    expect(
      h['Authorization'],
      'Basic ${base64.encode(utf8.encode('user:pw'))}',
    );
  });

  test('basic auth for qBittorrent adds no header (client logs in)', () {
    final h = buildAuthHeaders(
      profile(ServiceKind.qbittorrent, AuthMode.basic),
      const ServerCredentials(username: 'user', password: 'pw'),
    );
    expect(h, isEmpty);
  });

  test('none adds nothing; missing secrets add nothing', () {
    expect(
      buildAuthHeaders(
        profile(ServiceKind.sonarr, AuthMode.none),
        const ServerCredentials(apiKey: 'x'),
      ),
      isEmpty,
    );
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
