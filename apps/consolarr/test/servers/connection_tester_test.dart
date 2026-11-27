// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/auth_headers.dart';
import 'package:consolarr/features/servers/application/connection_tester.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/service_kind_info.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
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

class _RecordingAnalytics implements Analytics {
  final List<String> events = [];
  final List<Map<String, Object>> params = [];
  @override
  Future<void> setEnabled({required bool enabled}) async {}
  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async {
    events.add(name);
    params.add(parameters);
  }
}

ServerProfile profile(ServiceKind kind, {String prefix = ''}) =>
    ServerProfile.parse(
      id: 'p1',
      name: 'n',
      kind: kind,
      address: 'https://host.example',
      pathPrefix: prefix,
      authMode: kind == ServiceKind.sonarr ? AuthMode.apiKey : AuthMode.basic,
    ).valueOrNull!;

ResponseBody json(String body, [int status = 200]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const sonarrKey = ServerCredentials(apiKey: 'test-key-0000');
const qbitCreds = ServerCredentials(username: 'admin', password: 'pw');

Future<ConnectionTestOutcome> run(
  HttpClientAdapter adapter,
  ServerProfile p,
  ServerCredentials c, {
  _Factory? factory,
}) => DefaultConnectionTester(factory ?? _Factory(adapter)).test(p, c);

AppError failure(ConnectionTestOutcome o) => (o as ConnectionTestFailure).error;

void main() {
  group('Sonarr', () {
    test(
      'success reports version and major, sends the key in a header',
      () async {
        final f = _Factory(
          StubAdapter(
            (o) => json('{"version":"4.0.9.2244","appName":"Sonarr"}'),
          ),
        );
        final r = await run(
          f.adapter,
          profile(ServiceKind.sonarr),
          sonarrKey,
          factory: f,
        );
        final ok = r as ConnectionTestSuccess;
        expect(ok.version, '4.0.9.2244');
        expect(ok.majorVersion, 4);
        expect(f.seen.single.headers['X-Api-Key'], 'test-key-0000');
        expect(f.seen.single.uri.toString(), isNot(contains('test-key')));
      },
    );

    test('path prefix is kept', () async {
      final f = _Factory(StubAdapter((o) => json('{"version":"3.0.10.1"}')));
      await run(
        f.adapter,
        profile(ServiceKind.sonarr, prefix: '/tv'),
        sonarrKey,
        factory: f,
      );
      expect(f.seen.single.uri.path, startsWith('/tv/api/'));
    });

    final cases =
        <String, (ResponseBody Function(RequestOptions), ErrorCategory)>{
          '401 -> auth_failed': (
            (o) => json('', 401),
            ErrorCategory.authFailed,
          ),
          '404 -> not_found (wrong prefix)': (
            (o) => json('', 404),
            ErrorCategory.notFound,
          ),
          '503 -> server_error': (
            (o) => json('', 503),
            ErrorCategory.serverError,
          ),
          'garbage body -> parse_error': (
            (o) => json('<html>nope</html>'),
            ErrorCategory.parseError,
          ),
          'version 2 -> unsupported_version': (
            (o) => json('{"version":"2.0.0.5344"}'),
            ErrorCategory.unsupportedVersion,
          ),
        };
    cases.forEach((name, c) {
      test(name, () async {
        final r = await run(
          StubAdapter(c.$1),
          profile(ServiceKind.sonarr),
          sonarrKey,
        );
        expect(failure(r).category, c.$2);
      });
    });

    test('timeout and dropped connection map to their categories', () async {
      final t = await run(
        FaultInjectingAdapter(
          inner: StubAdapter((o) => json('{}')),
          faults: const [TimeoutFault(kind: TimeoutKind.receive)],
        ),
        profile(ServiceKind.sonarr),
        sonarrKey,
      );
      expect(failure(t).category, ErrorCategory.timeout);
      final d = await run(
        FaultInjectingAdapter(
          inner: StubAdapter((o) => json('{}')),
          faults: const [ConnectionDropFault()],
        ),
        profile(ServiceKind.sonarr),
        sonarrKey,
      );
      expect(failure(d).category, ErrorCategory.networkUnreachable);
    });

    test('typed TLS errors pass through untouched', () async {
      final key = PinKey(profileId: 'p1', host: 'host.example', port: 443);
      final cert = CertificateDetails(
        fingerprint: CertificateFingerprint.parse('ab' * 32),
        subject: 'CN=example',
        issuer: 'CN=example',
        notBefore: DateTime.utc(2026),
        notAfter: DateTime.utc(2027),
      );
      final err = CertificateDecisionRequired(key: key, certificate: cert);
      final r = await run(
        StubAdapter((o) => throw DioException(requestOptions: o, error: err)),
        profile(ServiceKind.sonarr),
        sonarrKey,
      );
      expect(failure(r), isA<CertificateDecisionRequired>());
    });
  });

  group('qBittorrent', () {
    ResponseBody handler(RequestOptions o, {String login = 'Ok.'}) {
      if (o.path.endsWith('auth/login')) {
        return ResponseBody.fromString(
          login,
          200,
          headers: {
            'set-cookie': ['SID=abc; HttpOnly; path=/'],
          },
        );
      }
      return ResponseBody.fromString('v4.6.3', 200);
    }

    test('login then version', () async {
      final r = await run(
        StubAdapter(handler),
        profile(ServiceKind.qbittorrent),
        qbitCreds,
      );
      final ok = r as ConnectionTestSuccess;
      expect(ok.version, contains('4.6.3'));
      expect(ok.majorVersion, 4);
    });

    test('wrong password -> auth_failed', () async {
      final r = await run(
        StubAdapter((o) => handler(o, login: 'Fails.')),
        profile(ServiceKind.qbittorrent),
        qbitCreds,
      );
      expect(failure(r).category, ErrorCategory.authFailed);
    });
  });

  group('per-kind registry', () {
    test('a kind without a probe is not reported as an old version, and no '
        'request is made', () async {
      final factory = _Factory(StubAdapter((o) => json('{}')));
      // An injected, empty registry: the test must not depend on which kinds
      // have a probe today (every service branch registers its own).
      for (final kind in [ServiceKind.radarr, ServiceKind.sonarr]) {
        final r = await DefaultConnectionTester(
          factory,
          probes: const {},
        ).test(profile(kind), sonarrKey);
        final error = failure(r);
        expect(error.category, isNot(ErrorCategory.unsupportedVersion));
        expect(error.debugDetail, contains('no connection probe'));
      }
      expect(factory.seen, isEmpty);
    });

    test('every kind the editor offers has a probe and an auth builder', () {
      for (final kind in supportedServiceKinds) {
        expect(connectionProbes, contains(kind), reason: kind.name);
        expect(authHeaderBuilders, contains(kind), reason: kind.name);
      }
    });

    test('a probe can be injected (W4 services plug in here)', () async {
      final r = await DefaultConnectionTester(
        _Factory(StubAdapter((o) => json('{}'))),
        probes: {
          ServiceKind.radarr: (dio, profile, credentials) async =>
              const ConnectionTestSuccess(version: '5.0.0', majorVersion: 5),
        },
      ).test(profile(ServiceKind.radarr), sonarrKey);
      expect(r, isA<ConnectionTestSuccess>());
    });
  });

  group('TrackedConnectionTester', () {
    test('emits connection_test_result without any free text', () async {
      final analytics = _RecordingAnalytics();
      final tracker = EventTracker(
        analytics: analytics,
        breadcrumbs: Breadcrumbs(),
      );
      final ok = TrackedConnectionTester(
        DefaultConnectionTester(
          _Factory(StubAdapter((o) => json('{"version":"4.0.1"}'))),
        ),
        tracker,
      );
      await ok.test(profile(ServiceKind.sonarr), sonarrKey);
      final bad = TrackedConnectionTester(
        DefaultConnectionTester(_Factory(StubAdapter((o) => json('', 401)))),
        tracker,
      );
      await bad.test(profile(ServiceKind.sonarr), sonarrKey);
      expect(analytics.events, [
        'connection_test_result',
        'connection_test_result',
      ]);
      expect(analytics.params[0], {
        'service_kind': 'sonarr',
        'major_version': 4,
      });
      expect(analytics.params[1], {
        'service_kind': 'sonarr',
        'error_category': 'auth_failed',
      });
      final dump = analytics.params.toString();
      expect(dump, isNot(contains('host.example')));
      expect(dump, isNot(contains('test-key')));
    });
  });

  test('every core ErrorCategory has an observability counterpart', () {
    for (final c in ErrorCategory.values) {
      expect(ErrorCategoryParam.fromCode(c.code), isNotNull, reason: c.code);
    }
  });
}
