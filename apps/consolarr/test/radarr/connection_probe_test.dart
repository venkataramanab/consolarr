// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/connection_tester.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

class _Factory implements SecureHttpClientFactory {
  _Factory(this.adapter);
  final HttpClientAdapter adapter;
  final List<RequestOptions> seen = [];

  @override
  Dio create(ServerProfile profile) {
    final dio = Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          seen.add(o);
          h.next(o);
        },
      ),
    );
    return dio;
  }
}

ResponseBody _json(String body, [int status = 200]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ServerProfile _profile() => ServerProfile.parse(
  id: 'p1',
  name: 'n',
  kind: ServiceKind.radarr,
  address: 'https://radarr.example',
  authMode: AuthMode.apiKey,
).valueOrNull!;

void main() {
  test('Radarr is registered, offered and described', () {
    expect(connectionProbes, contains(ServiceKind.radarr));
    expect(supportedServiceKinds, contains(ServiceKind.radarr));
  });

  test('success reports the version; the key travels in a header', () async {
    final f = _Factory(
      StubAdapter((o) => _json('{"version":"5.2.1.8609","appName":"Radarr"}')),
    );
    final r = await DefaultConnectionTester(f)
        .test(_profile(), const ServerCredentials(apiKey: 'test-key-0000'));
    final ok = r as ConnectionTestSuccess;
    expect(ok.majorVersion, 5);
    expect(f.seen.single.headers['X-Api-Key'], 'test-key-0000');
    expect(f.seen.single.uri.toString(), isNot(contains('test-key')));
  });

  test('an old Radarr is unsupported_version', () async {
    final f = _Factory(StubAdapter((o) => _json('{"version":"0.2.0.1"}')));
    final r = await DefaultConnectionTester(f)
        .test(_profile(), const ServerCredentials(apiKey: 'k'));
    expect(
      (r as ConnectionTestFailure).error.category,
      ErrorCategory.unsupportedVersion,
    );
  });

  test('a missing api/v3 is not_found (wrong address or prefix)', () async {
    final f = _Factory(StubAdapter((o) => _json('', 404)));
    final r = await DefaultConnectionTester(f)
        .test(_profile(), const ServerCredentials(apiKey: 'k'));
    expect((r as ConnectionTestFailure).error.category, ErrorCategory.notFound);
  });
}
