// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';

import 'certs.dart';

/// One request as the server saw it.
class SeenRequest {
  SeenRequest(this.method, this.uri, this.headers);

  final String method;
  final Uri uri;

  /// Lower-case header name -> value.
  final Map<String, String> headers;
}

typedef Handler = FutureOr<void> Function(HttpRequest request);

/// A local server (TLS when [cert] is given) that records every request.
class TestServer {
  TestServer._(this._server, this.cert, this._handler);

  final HttpServer _server;
  final TestCert? cert;
  Handler _handler;
  final List<SeenRequest> seen = [];

  static Future<TestServer> start({TestCert? cert, Handler? handler}) async {
    final HttpServer server;
    if (cert == null) {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } else {
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        cert.serverContext(),
      );
    }
    final ts = TestServer._(server, cert, handler ?? _ok);
    server.listen(ts._onRequest);
    return ts;
  }

  static void _ok(HttpRequest r) {
    r.response
      ..headers.contentType = ContentType.json
      ..write('{"ok":true}');
  }

  set handler(Handler h) => _handler = h;

  Future<void> _onRequest(HttpRequest r) async {
    final headers = <String, String>{};
    r.headers.forEach((name, values) => headers[name] = values.join(','));
    seen.add(SeenRequest(r.method, r.uri, headers));
    try {
      await _handler(r);
    } finally {
      await r.response.close();
    }
  }

  int get port => _server.port;
  String get scheme => cert == null ? 'http' : 'https';
  Uri get origin => Uri.parse('$scheme://127.0.0.1:$port');

  ServerProfile profile({
    String id = 'p1',
    bool allowCleartext = false,
    AuthMode authMode = AuthMode.apiKey,
  }) => ServerProfile.parse(
    id: id,
    name: 'Test',
    kind: ServiceKind.sonarr,
    address: origin.toString(),
    allowCleartext: allowCleartext,
    authMode: authMode,
  ).valueOrNull!;

  Future<void> close() => _server.close(force: true);
}
