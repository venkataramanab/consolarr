// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core/core.dart';
import 'package:security/security.dart';
import 'package:test/test.dart';

void main() {
  test('the adapter reports the final hop, not the first URI', () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final home = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await other.close(force: true);
      await home.close(force: true);
    });
    other.listen((r) async {
      r.response.write('end');
      await r.response.close();
    });
    home.listen((r) async {
      r.response
        ..statusCode = 302
        ..headers.set('location', 'http://127.0.0.1:${other.port}/final');
      await r.response.close();
    });
    final profile = ServerProfile.parse(
      id: 'p',
      name: 'n',
      kind: ServiceKind.qbittorrent,
      address: 'http://127.0.0.1:${home.port}',
      allowCleartext: true,
    ).valueOrNull!;
    final dio = DefaultSecureHttpClientFactory(pins: InMemoryPinStore())
        .create(profile);
    final response = await dio.get<String>('/start');
    final reported = response.extra[finalUriExtraKey]! as Uri;
    expect(reported.port, other.port);
    expect(reported.path, '/final');
    // Why the key exists: realUri shows the original request.
    expect(response.realUri.port, home.port);
  });

  test('without a redirect the final hop is the request URI', () async {
    final home = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => home.close(force: true));
    home.listen((r) async {
      r.response.write('ok');
      await r.response.close();
    });
    final profile = ServerProfile.parse(
      id: 'p',
      name: 'n',
      kind: ServiceKind.qbittorrent,
      address: 'http://127.0.0.1:${home.port}',
      allowCleartext: true,
    ).valueOrNull!;
    final response = await DefaultSecureHttpClientFactory(
      pins: InMemoryPinStore(),
    ).create(profile).get<String>('/a');
    expect((response.extra[finalUriExtraKey]! as Uri).path, '/a');
  });
}
