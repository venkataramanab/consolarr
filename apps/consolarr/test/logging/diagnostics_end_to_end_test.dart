// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';
import 'package:test_harness/test_harness.dart';

// Canaries that must never show up in the diagnostics view.
const _host = 'radarr-canary.invalid';
const _key = 'test-key-CANARY0000';
const _address = 'https://$_host:7878';

class _Factory implements SecureHttpClientFactory {
  _Factory(this.status);
  final int status;

  @override
  Dio create(ServerProfile profile) =>
      Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
        ..httpClientAdapter = StubAdapter(
          (o) => ResponseBody.fromString(
            status == 200 ? '{"version":"5.2.0"}' : '',
            status,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  Future<ProviderContainer> start({required int status}) async {
    db = AppDatabase.memory();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        secureHttpClientFactoryProvider.overrideWithValue(_Factory(status)),
      ],
    );
    container.read(firstFrameDoneProvider.notifier).markDone();
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ServerEntry> addRadarr() async =>
      (await container
              .read(serverRepositoryProvider)
              .save(
                const ServerDraft(
                  name: 'Example Radarr',
                  kind: ServiceKind.radarr,
                  address: _address,
                  credentials: ServerCredentials(apiKey: _key),
                ),
              ))
          .valueOrNull!;

  List<String> lines(DiagnosticsLogView view) => [
    for (var i = 0; i < view.length; i++) view.entryAt(i).message,
  ];

  test('debug diagnostics capture a failed connection test and a failed list '
      'load, redacted', () async {
    await start(status: 401);
    final settings = container.read(settingsProvider.notifier);
    await settings.setDiagnosticsEnabled(true);
    await settings.setDiagnosticsLevel(LogLevel.debug);
    final sub = container.listen(diagnosticsLogViewProvider, (_, _) {});
    addTearDown(sub.close);
    expect(sub.read().enabled, isTrue);
    expect(sub.read().isEmpty, isTrue);

    final entry = await addRadarr();
    final credentials = await container
        .read(serverRepositoryProvider)
        .loadCredentials(entry.profile);

    // 1. The connection test.
    final outcome = await container
        .read(connectionTesterProvider)
        .test(entry.profile, credentials);
    expect(
      (outcome as ConnectionTestFailure).error.category,
      ErrorCategory.authFailed,
    );

    // 2. A Radarr list load.
    await container
        .read(movieLibraryProvider.future)
        .then((_) {}, onError: (Object _) {});
    final library = container.read(movieLibraryProvider);
    expect(library.hasError || library.value != null, isTrue);

    final out = lines(sub.read());
    expect(
      out,
      contains(
        matches(
          RegExp(
            r'^GET api·v3·system·status failed category=auth_failed status=401, \d+ms$',
          ),
        ),
      ),
    );
    expect(out, contains('connection_test kind=radarr result=auth_failed'));
    expect(
      out,
      contains(
        matches(
          RegExp(
            r'^GET api·v3·movie failed category=auth_failed status=401, \d+ms$',
          ),
        ),
      ),
    );

    // Redacted: nothing identifying anywhere in what the user can see/share.
    final all = out.join('\n');
    for (final secret in [_host, '7878', _key, 'CANARY', 'Example Radarr']) {
      expect(all, isNot(contains(secret)), reason: secret);
    }
    // The shared bundle redacts again; the same holds for the entries it holds.
    final bundleEntries = container.read(diagnosticsLogProvider).entries;
    expect(bundleEntries.map((e) => e.message).join(), isNot(contains(_key)));
  });

  test('successful requests are logged at debug and only at debug', () async {
    await start(status: 200);
    final settings = container.read(settingsProvider.notifier);
    await settings.setDiagnosticsEnabled(true);
    final sub = container.listen(diagnosticsLogViewProvider, (_, _) {});
    addTearDown(sub.close);
    final entry = await addRadarr();
    final credentials = await container
        .read(serverRepositoryProvider)
        .loadCredentials(entry.profile);
    final tester = container.read(connectionTesterProvider);

    await settings.setDiagnosticsLevel(LogLevel.info);
    await tester.test(entry.profile, credentials);
    var out = lines(sub.read());
    expect(out, contains('connection_test kind=radarr result=ok'));
    expect(out.where((l) => l.contains('->')), isEmpty);

    await settings.setDiagnosticsLevel(LogLevel.debug);
    await tester.test(entry.profile, credentials);
    out = lines(sub.read());
    expect(
      out,
      contains(matches(RegExp(r'^GET api·v3·system·status -> 200, \d+ms$'))),
    );
  });
}
