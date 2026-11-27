// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/data/drift_server_repository.dart';
import 'package:consolarr/features/servers/data/server_secret_keys.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';

void main() {
  late AppDatabase db;
  late InMemorySecretStore secrets;
  late DriftPayloadCache cache;
  late DriftServerRepository repo;
  late List<ServiceKind> added;

  setUp(() {
    db = AppDatabase.memory();
    secrets = InMemorySecretStore();
    cache = DriftPayloadCache(db);
    added = [];
    repo = DriftServerRepository(
      db: db,
      secrets: secrets,
      cache: cache,
      onServerAdded: (p) => added.add(p.kind),
    );
  });
  tearDown(() => db.close());

  ServerDraft sonarr({
    String? id,
    String name = 'Example Sonarr',
    String address = 'https://sonarr.example',
    ServerCredentials credentials = const ServerCredentials(
      apiKey: 'test-key-0000',
    ),
    AuthMode authMode = AuthMode.apiKey,
    bool allowCleartext = false,
    String pathPrefix = '',
  }) => ServerDraft(
    id: id,
    name: name,
    kind: ServiceKind.sonarr,
    address: address,
    pathPrefix: pathPrefix,
    authMode: authMode,
    allowCleartext: allowCleartext,
    credentials: credentials,
  );

  test(
    'save creates a server, stores the key only in the secret store',
    () async {
      final r = await repo.save(sonarr());
      final entry = r.valueOrNull!;
      expect(entry.profile.id, isNotEmpty);
      expect(entry.needsCredentials, isFalse);
      expect(entry.profile.allowCleartext, isFalse);
      expect(
        await secrets.read(ServerSecretKeys.apiKey(entry.profile.id)),
        'test-key-0000',
      );
      final rows = await db.select(db.serverRows).get();
      expect(rows.single.toString(), isNot(contains('test-key-0000')));
      expect(added, [ServiceKind.sonarr]);
    },
  );

  test('generated ids are unique hex strings', () async {
    final a = (await repo.save(sonarr())).valueOrNull!.profile.id;
    final b = (await repo.save(sonarr())).valueOrNull!.profile.id;
    expect(a, isNot(b));
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('editing keeps the id and does not report a new server', () async {
    final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
    final r = await repo.save(sonarr(id: id, name: 'Renamed'));
    expect(r.valueOrNull!.profile.id, id);
    expect((await repo.find(id))!.profile.name, 'Renamed');
    expect(added, hasLength(1));
    expect(await db.select(db.serverRows).get(), hasLength(1));
  });

  test(
    'null credential fields keep stored secrets; empty strings delete',
    () async {
      final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
      await repo.save(sonarr(id: id, credentials: ServerCredentials.empty));
      expect(await secrets.read(ServerSecretKeys.apiKey(id)), 'test-key-0000');
      await repo.save(
        sonarr(
          id: id,
          credentials: const ServerCredentials(apiKey: ''),
        ),
      );
      expect(await secrets.read(ServerSecretKeys.apiKey(id)), isNull);
      expect((await repo.find(id))!.needsCredentials, isTrue);
    },
  );

  test('rejects credentials and query strings in the address', () async {
    for (final bad in [
      'https://user:pw@sonarr.example',
      'https://sonarr.example/?apikey=abc',
    ]) {
      final r = await repo.save(sonarr(address: bad));
      expect(r.errorOrNull!.category, ErrorCategory.parseError, reason: bad);
    }
    expect(await db.select(db.serverRows).get(), isEmpty);
    expect(added, isEmpty);
  });

  test('changing the auth mode deletes secrets of the old mode', () async {
    final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
    await repo.save(
      sonarr(
        id: id,
        authMode: AuthMode.basic,
        credentials: const ServerCredentials(username: 'u', password: 'p'),
      ),
    );
    expect(await secrets.read(ServerSecretKeys.apiKey(id)), isNull);
    expect(await secrets.read(ServerSecretKeys.username(id)), 'u');
    await repo.save(
      sonarr(
        id: id,
        authMode: AuthMode.none,
        credentials: ServerCredentials.empty,
      ),
    );
    expect(await secrets.read(ServerSecretKeys.username(id)), isNull);
    expect(await secrets.read(ServerSecretKeys.password(id)), isNull);
    expect((await repo.find(id))!.needsCredentials, isFalse);
  });

  test('custom headers: names in the profile, values in secrets', () async {
    final id = (await repo.save(
      sonarr(
        authMode: AuthMode.none,
        credentials: const ServerCredentials(
          headers: [
            HeaderEntry(name: 'X-Gateway', value: 'v1'),
            HeaderEntry(name: 'X-Other', value: 'v2'),
          ],
        ),
      ),
    )).valueOrNull!.profile.id;
    final entry = (await repo.find(id))!;
    expect(entry.profile.headerNames, ['X-Gateway', 'X-Other']);
    expect(await secrets.read(ServerSecretKeys.header(id, 'X-Gateway')), 'v1');
    final creds = await repo.loadCredentials(entry.profile);
    expect(creds.headers.map((h) => '${h.name}=${h.value}'), [
      'X-Gateway=v1',
      'X-Other=v2',
    ]);
    // Removing a header deletes its secret.
    await repo.save(
      sonarr(
        id: id,
        authMode: AuthMode.none,
        credentials: const ServerCredentials(
          headers: [HeaderEntry(name: 'X-Gateway', value: 'v1')],
        ),
      ),
    );
    expect(await secrets.read(ServerSecretKeys.header(id, 'X-Other')), isNull);
  });

  test('Keystore loss marks needsCredentials and never throws', () async {
    final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
    secrets.simulateKeystoreLoss();
    final entry = (await repo.find(id))!;
    expect(entry.needsCredentials, isTrue);
    expect((await repo.watchAll().first).single.needsCredentials, isTrue);
    final creds = await repo.loadCredentials(entry.profile);
    expect(creds.apiKey, isNull);
    // Re-entry fixes it.
    await repo.save(sonarr(id: id));
    expect((await repo.find(id))!.needsCredentials, isFalse);
  });

  test('delete removes row, secrets, pin and cached payloads', () async {
    final entry = (await repo.save(sonarr())).valueOrNull!;
    final id = entry.profile.id;
    final pinKey = PinKey.forProfile(entry.profile);
    await secrets.write(pinKey.storageKey, '0' * 64);
    await cache.write(id, 'sonarr.series', '[]', DateTime.utc(2026));
    await repo.save(sonarr(name: 'Other'));
    await repo.delete(id);
    expect(await repo.find(id), isNull);
    expect(await secrets.read(ServerSecretKeys.apiKey(id)), isNull);
    expect(await secrets.read(pinKey.storageKey), isNull);
    expect(await cache.read(id, 'sonarr.series'), isNull);
    expect(await repo.watchAll().first, hasLength(1));
  });

  test('order: new servers append; reorder persists', () async {
    final a = (await repo.save(sonarr(name: 'A'))).valueOrNull!.profile.id;
    final b = (await repo.save(sonarr(name: 'B'))).valueOrNull!.profile.id;
    final c = (await repo.save(sonarr(name: 'C'))).valueOrNull!.profile.id;
    expect((await repo.watchAll().first).map((e) => e.profile.id), [a, b, c]);
    await repo.reorder([c, a]);
    expect((await repo.watchAll().first).map((e) => e.profile.id), [c, a, b]);
  });

  test(
    'startup server: at most one, can be cleared, cleared on delete',
    () async {
      final a = (await repo.save(sonarr(name: 'A'))).valueOrNull!.profile.id;
      final b = (await repo.save(sonarr(name: 'B'))).valueOrNull!.profile.id;
      await repo.setStartup(a);
      await repo.setStartup(b);
      final list = await repo.watchAll().first;
      expect(list.where((e) => e.isStartup).map((e) => e.profile.id), [b]);
      await repo.setStartup(null);
      expect((await repo.watchAll().first).any((e) => e.isStartup), isFalse);
      await repo.setStartup(b);
      await repo.delete(b);
      expect((await repo.watchAll().first).any((e) => e.isStartup), isFalse);
    },
  );

  test('active server per kind: explicit, fallback, none', () async {
    expect(await repo.activeId(ServiceKind.sonarr), isNull);
    final a = (await repo.save(sonarr(name: 'A'))).valueOrNull!.profile.id;
    final b = (await repo.save(sonarr(name: 'B'))).valueOrNull!.profile.id;
    expect(await repo.activeId(ServiceKind.sonarr), a);
    await repo.setActive(ServiceKind.sonarr, b);
    expect(await repo.activeId(ServiceKind.sonarr), b);
    await repo.delete(b);
    expect(await repo.activeId(ServiceKind.sonarr), a);
    expect(await repo.activeId(ServiceKind.qbittorrent), isNull);
  });

  test('cleartext opt-in and path prefix round-trip', () async {
    final id = (await repo.save(
      sonarr(
        address: 'http://192.0.2.10:8989',
        allowCleartext: true,
        pathPrefix: 'tv/',
      ),
    )).valueOrNull!.profile.id;
    final p = (await repo.find(id))!.profile;
    expect(p.allowCleartext, isTrue);
    expect(p.pathPrefix, '/tv');
    expect(p.address.port, 8989);
  });

  test('watchAll emits again after changes', () async {
    final emissions = <int>[];
    final sub = repo.watchAll().listen((l) => emissions.add(l.length));
    await repo.save(sonarr());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.last, 1);
  });
}
