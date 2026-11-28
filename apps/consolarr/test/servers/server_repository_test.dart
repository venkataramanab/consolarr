// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/data/drift_server_repository.dart';
import 'package:consolarr/features/servers/data/server_secret_keys.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show Value;
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
    ServerDraft qbit({
      String? id,
      AuthMode authMode = AuthMode.apiKey,
      ServerCredentials credentials = ServerCredentials.empty,
    }) => ServerDraft(
      id: id,
      name: 'Example qBittorrent',
      kind: ServiceKind.qbittorrent,
      address: 'https://qbit.example',
      authMode: authMode,
      credentials: credentials,
    );
    final id = (await repo.save(
      qbit(credentials: const ServerCredentials(apiKey: 'test-key-0000')),
    )).valueOrNull!.profile.id;
    await repo.save(
      qbit(
        id: id,
        authMode: AuthMode.basic,
        credentials: const ServerCredentials(username: 'u', password: 'p'),
      ),
    );
    expect(await secrets.read(ServerSecretKeys.apiKey(id)), isNull);
    expect(await secrets.read(ServerSecretKeys.username(id)), 'u');
    await repo.save(qbit(id: id, authMode: AuthMode.none));
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

  test(
    'delete also removes the server-scoped state (Deluge daemon host)',
    () async {
      final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
      final other = (await repo.save(sonarr(name: 'Other')))
          .valueOrNull!
          .profile
          .id;
      for (final sid in [id, other]) {
        await db
            .into(db.appStateRows)
            .insertOnConflictUpdate(
              AppStateRowsCompanion.insert(
                key: 'torrents.deluge_host.$sid',
                value: 'host-of-$sid',
              ),
            );
      }
      await repo.delete(id);
      final keys = [
        for (final r in await db.select(db.appStateRows).get()) r.key,
      ];
      expect(keys, isNot(contains('torrents.deluge_host.$id')));
      expect(keys, contains('torrents.deluge_host.$other'));
    },
  );

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

  group('hardening (W3b)', () {
    test(
      'an unreadable Keystore reads as needsCredentials, never throws',
      () async {
        final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
        secrets.unavailable = true;
        expect((await repo.find(id))!.needsCredentials, isTrue);
        final creds = await repo.loadCredentials(
          (await repo.find(id))!.profile,
        );
        expect(creds.apiKey, isNull);
      },
    );

    test('delete removes a row whose address no longer parses, with its '
        'secrets', () async {
      const id = 'bad-port-row';
      await db
          .into(db.serverRows)
          .insert(
            ServerRowsCompanion.insert(
              id: id,
              name: 'Broken',
              kind: 'sonarr',
              address: 'https://nas.example:99999',
              authMode: 'apiKey',
              headerNames: const Value('X-One'),
              alternateAddress: const Value('https://alt.example:0'),
            ),
          );
      await secrets.write(ServerSecretKeys.apiKey(id), 'test-key-0000');
      await secrets.write(ServerSecretKeys.header(id, 'X-One'), 'v');
      await cache.write(id, 'sonarr.series', '[]', DateTime.utc(2026));

      await repo.delete(id);

      expect(await db.select(db.serverRows).get(), isEmpty);
      expect(await secrets.read(ServerSecretKeys.apiKey(id)), isNull);
      expect(await secrets.read(ServerSecretKeys.header(id, 'X-One')), isNull);
      expect(await cache.read(id, 'sonarr.series'), isNull);
    });

    test('save rejects out-of-range ports', () async {
      final r = await repo.save(sonarr(address: 'https://nas.example:99999'));
      expect(r.errorOrNull?.category, ErrorCategory.parseError);
      expect(await db.select(db.serverRows).get(), isEmpty);
    });

    test('save keeps the alternate address', () async {
      final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
      await (db.update(db.serverRows)..where((r) => r.id.equals(id))).write(
        const ServerRowsCompanion(
          alternateAddress: Value('https://alt.example:8443'),
        ),
      );
      await repo.save(sonarr(id: id, name: 'Renamed'));
      final p = (await repo.find(id))!.profile;
      expect(p.alternateAddress.toString(), 'https://alt.example:8443');
      expect(p.name, 'Renamed');
    });

    test(
      'editing the identity clears cached payloads and the old pin',
      () async {
        final entry = (await repo.save(sonarr())).valueOrNull!;
        final id = entry.profile.id;
        final oldPin = PinKey.forProfile(entry.profile);
        await secrets.write(oldPin.storageKey, '0' * 64);
        await cache.write(id, 'sonarr.series', '[]', DateTime.utc(2026));

        // A rename alone keeps both.
        await repo.save(sonarr(id: id, name: 'Renamed'));
        expect(await cache.read(id, 'sonarr.series'), isNotNull);
        expect(await secrets.read(oldPin.storageKey), isNotNull);

        for (final changed in [
          sonarr(id: id, address: 'https://other.example'),
        ]) {
          await repo.save(changed);
        }
        expect(await cache.read(id, 'sonarr.series'), isNull);
        expect(await secrets.read(oldPin.storageKey), isNull);

        // Path prefix changes are identity changes too.
        await cache.write(id, 'sonarr.series', '[]', DateTime.utc(2026));
        await repo.save(
          sonarr(id: id, address: 'https://other.example', pathPrefix: '/tv'),
        );
        expect(await cache.read(id, 'sonarr.series'), isNull);
      },
    );

    test(
      'changing the origin drops secrets that are not re-supplied',
      () async {
        final id = (await repo.save(
          sonarr(
            credentials: const ServerCredentials(
              apiKey: 'test-key-0000',
              headers: [HeaderEntry(name: 'X-One', value: 'v1')],
            ),
          ),
        )).valueOrNull!.profile.id;

        final r = await repo.save(
          sonarr(
            id: id,
            address: 'https://other.example',
            credentials: const ServerCredentials(),
          ),
        );
        expect(r.valueOrNull!.needsCredentials, isTrue);
        expect(await secrets.read(ServerSecretKeys.apiKey(id)), isNull);

        // Re-entering works.
        final again = await repo.save(
          sonarr(
            id: id,
            address: 'https://other.example',
            credentials: const ServerCredentials(apiKey: 'test-key-1111'),
          ),
        );
        expect(again.valueOrNull!.needsCredentials, isFalse);
      },
    );

    test('a same-origin edit keeps secrets', () async {
      final id = (await repo.save(sonarr())).valueOrNull!.profile.id;
      await repo.save(
        sonarr(
          id: id,
          pathPrefix: '/tv',
          credentials: const ServerCredentials(),
        ),
      );
      expect(await secrets.read(ServerSecretKeys.apiKey(id)), 'test-key-0000');
    });
  });

  group('watchConnectionKey', () {
    test('emits on credential edits and on set-active, not on noise', () async {
      final a = (await repo.save(sonarr(name: 'A'))).valueOrNull!.profile.id;
      final b = (await repo.save(sonarr(name: 'B'))).valueOrNull!.profile.id;
      final keys = <ConnectionKey>[];
      final sub = repo.watchConnectionKey(ServiceKind.sonarr).listen(keys.add);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();
      expect(keys.last.serverId, a);

      await repo.save(
        sonarr(
          id: a,
          credentials: const ServerCredentials(apiKey: 'test-key-2222'),
        ),
      );
      await settle();
      final afterEdit = keys.last;
      expect(afterEdit.serverId, a);
      expect(afterEdit, isNot(keys.first));

      await repo.setActive(ServiceKind.sonarr, b);
      await settle();
      expect(keys.last.serverId, b);

      // Unrelated writes (another kind) do not re-emit the same value.
      final count = keys.length;
      await repo.setActive(ServiceKind.qbittorrent, 'x');
      await settle();
      expect(keys.length, count);
      await sub.cancel();
    });
  });

  group('Sonarr and Radarr credentials', () {
    test('the key and a proxy login are stored side by side', () async {
      final entry = (await repo.save(
        sonarr(
          credentials: const ServerCredentials(
            apiKey: 'test-key-0000',
            username: 'user',
            password: 'pw',
          ),
        ),
      )).valueOrNull!;
      final id = entry.profile.id;
      expect(entry.profile.authMode, AuthMode.apiKey);
      expect(entry.proxyLogin, isTrue);
      expect(entry.needsCredentials, isFalse);
      expect(await secrets.read(ServerSecretKeys.apiKey(id)), 'test-key-0000');
      expect(await secrets.read(ServerSecretKeys.username(id)), 'user');
      expect(await secrets.read(ServerSecretKeys.password(id)), 'pw');
      final c = await repo.loadCredentials(entry.profile);
      expect(c.apiKey, 'test-key-0000');
      expect(c.username, 'user');
    });

    test(
      'no proxy login by default; empty strings delete a stored one',
      () async {
        final id = (await repo.save(
          sonarr(
            credentials: const ServerCredentials(
              apiKey: 'test-key-0000',
              username: 'user',
              password: 'pw',
            ),
          ),
        )).valueOrNull!.profile.id;
        // Keeping (null) leaves it alone.
        var e = (await repo.save(
          sonarr(id: id, credentials: ServerCredentials.empty),
        )).valueOrNull!;
        expect(e.proxyLogin, isTrue);
        e = (await repo.save(
          sonarr(
            id: id,
            credentials: const ServerCredentials(username: '', password: ''),
          ),
        )).valueOrNull!;
        expect(e.proxyLogin, isFalse);
        expect(await secrets.read(ServerSecretKeys.username(id)), isNull);
        expect(
          await secrets.read(ServerSecretKeys.apiKey(id)),
          'test-key-0000',
        );
      },
    );

    test('an arr server without a key needs credentials in any mode', () async {
      for (final mode in AuthMode.values) {
        final e = (await repo.save(
          sonarr(
            name: 'S ${mode.name}',
            authMode: mode,
            credentials: ServerCredentials.empty,
          ),
        )).valueOrNull!;
        expect(e.needsCredentials, isTrue, reason: mode.name);
      }
    });

    group('migration of profiles saved in the old basic mode', () {
      Future<String> seedOldBasic({
        ServiceKind kind = ServiceKind.radarr,
        bool withLogin = true,
      }) async {
        await db
            .into(db.serverRows)
            .insert(
              ServerRowsCompanion.insert(
                id: 'old1',
                name: 'Example Radarr',
                kind: kind.name,
                address: 'https://radarr.example',
                authMode: AuthMode.basic.name,
              ),
            );
        if (withLogin) {
          await secrets.write(ServerSecretKeys.username('old1'), 'user');
          await secrets.write(ServerSecretKeys.password('old1'), 'pw');
        }
        return 'old1';
      }

      test(
        'loads, needs the API key, keeps the login as proxy login',
        () async {
          final id = await seedOldBasic();
          final e = (await repo.find(id))!;
          expect(e.profile.authMode, AuthMode.basic);
          expect(e.isLegacyArrAuth, isTrue);
          expect(e.needsCredentials, isTrue);
          expect(e.proxyLogin, isTrue);
          final c = await repo.loadCredentials(e.profile);
          expect(c.username, 'user');
          expect(c.password, 'pw');
        },
      );

      test('saving the key upgrades the profile and loses nothing', () async {
        final id = await seedOldBasic();
        final saved = (await repo.save(
          ServerDraft(
            id: id,
            name: 'Example Radarr',
            kind: ServiceKind.radarr,
            address: 'https://radarr.example',
            credentials: const ServerCredentials(apiKey: 'test-key-0000'),
          ),
        )).valueOrNull!;
        expect(saved.profile.authMode, AuthMode.apiKey);
        expect(saved.isLegacyArrAuth, isFalse);
        expect(saved.needsCredentials, isFalse);
        expect(saved.proxyLogin, isTrue);
        expect(await secrets.read(ServerSecretKeys.username(id)), 'user');
        expect(await secrets.read(ServerSecretKeys.password(id)), 'pw');
      });

      test('an old none profile needs the key but does not break', () async {
        await db
            .into(db.serverRows)
            .insert(
              ServerRowsCompanion.insert(
                id: 'old2',
                name: 'Example Sonarr',
                kind: ServiceKind.sonarr.name,
                address: 'https://sonarr.example',
                authMode: AuthMode.none.name,
              ),
            );
        final e = (await repo.find('old2'))!;
        expect(e.isLegacyArrAuth, isTrue);
        expect(e.needsCredentials, isTrue);
        expect(e.proxyLogin, isFalse);
      });

      test('torrent profiles in basic mode are unchanged', () async {
        final id = await seedOldBasic(kind: ServiceKind.qbittorrent);
        final e = (await repo.find(id))!;
        expect(e.isLegacyArrAuth, isFalse);
        expect(e.needsCredentials, isFalse);
        expect(e.proxyLogin, isFalse);
      });
    });
  });
}
