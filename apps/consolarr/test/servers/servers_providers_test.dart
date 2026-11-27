// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/connection_tester.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

class _Factory implements SecureHttpClientFactory {
  @override
  Dio create(ServerProfile profile) =>
      Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
        ..httpClientAdapter = StubAdapter.json('{"version":"4.0.1"}');
}

class _Tester implements ConnectionTester {
  _Tester(this.outcome);
  ConnectionTestOutcome outcome;
  int calls = 0;
  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials credentials,
  ) async {
    calls++;
    return outcome;
  }
}

class _Analytics implements Analytics {
  final List<String> events = [];
  @override
  Future<void> setEnabled({required bool enabled}) async {}
  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async => events.add(name);
}

void main() {
  late AppDatabase db;
  late InMemorySecretStore secrets;
  late _Analytics analytics;
  late _Tester tester;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.memory();
    secrets = InMemorySecretStore();
    analytics = _Analytics();
    tester = _Tester(const ConnectionTestSuccess(version: '4.0.1'));
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(secrets),
        secureHttpClientFactoryProvider.overrideWithValue(_Factory()),
        analyticsProvider.overrideWithValue(analytics),
        healthTesterProvider.overrideWithValue(tester),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<String> addSonarr() async {
    final repo = container.read(serverRepositoryProvider);
    final r = await repo.save(
      const ServerDraft(
        name: 'Example',
        kind: ServiceKind.sonarr,
        address: 'https://sonarr.example',
        credentials: ServerCredentials(apiKey: 'test-key-0000'),
      ),
    );
    return r.valueOrNull!.profile.id;
  }

  test('no server of the kind -> null connection', () async {
    expect(
      await container.read(activeConnectionProvider(ServiceKind.sonarr).future),
      isNull,
    );
  });

  test('active connection carries the key header and base URL', () async {
    final id = await addSonarr();
    final c = (await container.read(
      activeConnectionProvider(ServiceKind.sonarr).future,
    ))!;
    expect(c.profile.id, id);
    expect(c.dio.options.headers['X-Api-Key'], 'test-key-0000');
    expect(c.dio.options.baseUrl, 'https://sonarr.example');
  });

  test(
    'Keystore loss -> auth_failed needs_credentials, never a crash',
    () async {
      await addSonarr();
      secrets.simulateKeystoreLoss();
      final f = container.read(
        activeConnectionProvider(ServiceKind.sonarr).future,
      );
      await expectLater(
        f,
        throwsA(
          isA<AppError>()
              .having((e) => e.category, 'category', ErrorCategory.authFailed)
              .having((e) => e.debugDetail, 'detail', 'needs_credentials'),
        ),
      );
    },
  );

  test('saving a new server reports server_added once', () async {
    await addSonarr();
    await Future<void>.delayed(Duration.zero);
    expect(analytics.events, ['server_added']);
  });

  group('health', () {
    test('success -> healthy; recheck runs the test again', () async {
      final id = await addSonarr();
      expect(
        await container.read(serverHealthProvider(id).future),
        ServerHealth.healthy,
      );
      container.invalidate(serverHealthProvider(id));
      await container.read(serverHealthProvider(id).future);
      expect(tester.calls, 2);
    });

    final mapping = {
      ErrorCategory.authFailed: ServerHealth.unauthorized,
      ErrorCategory.timeout: ServerHealth.degraded,
      ErrorCategory.serverError: ServerHealth.degraded,
      ErrorCategory.networkUnreachable: ServerHealth.unreachable,
      ErrorCategory.tlsPinMismatch: ServerHealth.unreachable,
    };
    mapping.forEach((cat, expected) {
      test('${cat.code} -> ${expected.name}', () {
        expect(
          healthFromOutcome(ConnectionTestFailure(AppError(cat))),
          expected,
        );
      });
    });

    test(
      'missing secrets -> unauthorized without contacting the server',
      () async {
        final id = await addSonarr();
        secrets.simulateKeystoreLoss();
        expect(
          await container.read(serverHealthProvider(id).future),
          ServerHealth.unauthorized,
        );
        expect(tester.calls, 0);
      },
    );

    test('loading state is checking (AsyncLoading)', () async {
      final id = await addSonarr();
      expect(container.read(serverHealthProvider(id)).isLoading, isTrue);
      await container.read(serverHealthProvider(id).future);
    });
  });
}
