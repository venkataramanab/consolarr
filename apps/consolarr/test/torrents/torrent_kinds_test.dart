// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:security/security.dart';

import '../servers/ui/support.dart' hide entry;
import '../servers/ui/support.dart' as ui show profile;
import 'support.dart';

/// Answers like the three clients' servers, with one torrent each whose name
/// says which server it came from.
class _KindAdapter implements HttpClientAdapter {
  _KindAdapter(this.kind);

  final ServiceKind kind;
  int requests = 0;

  ResponseBody _json(
    Object body, {
    int status = 200,
    Map<String, List<String>>? h,
  }) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?h,
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    requests++;
    final path = o.uri.path;
    switch (kind) {
      case ServiceKind.qbittorrent:
        if (path.endsWith('auth/login')) {
          return ResponseBody.fromString(
            'Ok.',
            200,
            headers: {
              'set-cookie': ['SID=x; path=/'],
            },
          );
        }
        if (path.endsWith('torrents/info')) {
          return _json([
            {
              'hash': 'q1',
              'name': 'Example qBittorrent ISO',
              'state': 'downloading',
              'progress': 0.5,
            },
          ]);
        }
        return _json({
          'dl_info_speed': 1,
          'up_info_speed': 1,
          'dl_info_data': 0,
          'up_info_data': 0,
        });
      case ServiceKind.transmission:
        if (o.headers['X-Transmission-Session-Id'] != 'tr-session') {
          return _json(
            {},
            status: 409,
            h: {
              'x-transmission-session-id': ['tr-session'],
            },
          );
        }
        final method = jsonDecode(o.data as String)['method'];
        if (method == 'torrent-get') {
          return _json({
            'result': 'success',
            'arguments': {
              'torrents': [
                {
                  'hashString': 't1',
                  'name': 'Example Transmission ISO',
                  'status': 4,
                  'percentDone': 0.2,
                },
              ],
            },
          });
        }
        return _json({
          'result': 'success',
          'arguments': {
            'downloadSpeed': 1,
            'uploadSpeed': 1,
            'cumulative-stats': {},
          },
        });
      default:
        final method = jsonDecode(o.data as String)['method'];
        Object? result = true;
        if (method == 'core.get_enabled_plugins') result = <String>[];
        if (method == 'core.get_torrents_status') {
          result = {
            'd1': {
              'name': 'Example Deluge ISO',
              'state': 'Downloading',
              'progress': 10.0,
            },
          };
        }
        if (method == 'core.get_session_status')
          result = {'payload_download_rate': 1, 'payload_upload_rate': 1};
        return _json(
          {'result': result, 'error': null, 'id': 1},
          h: method == 'auth.login'
              ? {
                  'set-cookie': ['_session_id=dl; Path=/'],
                }
              : null,
        );
    }
  }

  @override
  void close({bool force = false}) {}
}

class _Factory implements SecureHttpClientFactory {
  final adapters = <String, _KindAdapter>{};

  @override
  Dio create(ServerProfile profile) {
    final dio = Dio(BaseOptions(baseUrl: profile.baseUri.toString()));
    dio.httpClientAdapter = adapters.putIfAbsent(
      profile.id,
      () => _KindAdapter(profile.kind),
    );
    return dio;
  }
}

ServerEntry entry(
  String id, {
  required String name,
  required ServiceKind kind,
  required String address,
}) => ServerEntry(
  profile: ui.profile(
    id,
    name: name,
    kind: kind,
    address: address,
    authMode: AuthMode.basic,
  ),
  sortOrder: 0,
);

void main() {
  late FakeServerRepository repo;
  late _Factory factory;
  late ProviderContainer container;
  late AppDatabase db;

  setUp(() {
    repo =
        FakeServerRepository([
            entry(
              'qb',
              name: 'Example qBit',
              kind: ServiceKind.qbittorrent,
              address: 'https://qbit.example',
            ),
            entry(
              'tr',
              name: 'Example Transmission',
              kind: ServiceKind.transmission,
              address: 'https://transmission.example',
            ),
            entry(
              'dl',
              name: 'Example Deluge',
              kind: ServiceKind.deluge,
              address: 'https://deluge.example',
            ),
          ])
          ..credentials['qb'] = const ServerCredentials(
            username: 'u',
            password: 'p',
          )
          ..credentials['tr'] = const ServerCredentials(
            username: 'u',
            password: 'p',
          )
          ..credentials['dl'] = const ServerCredentials(password: 'p');
    factory = _Factory();
    db = AppDatabase.memory();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        serverRepositoryProvider.overrideWithValue(repo),
        secureHttpClientFactoryProvider.overrideWithValue(factory),
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => fixedNow),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
  });

  Future<void> select(ServiceKind kind, String id) async {
    await db
        .into(db.appStateRows)
        .insertOnConflictUpdate(
          AppStateRowsCompanion.insert(
            key: 'torrents.selected_kind',
            value: kind.name,
          ),
        );
    await repo.setActive(kind, id);
  }

  Future<String> settledName() async {
    // Wait out the reload that the selection started.
    for (var i = 0; i < 20; i++) {
      await pumpEventQueue();
      final v = container.read(torrentListProvider);
      if (!v.isLoading) break;
    }
    final v = container.read(torrentListProvider);
    expect(v.isLoading, isFalse);
    expect(v.hasError, isFalse, reason: '${v.error}');
    return (v.value! as TorrentsData).torrents.single.name;
  }

  test('without a choice the registry order picks the first kind', () async {
    final sub = container.listen(torrentListProvider, (_, _) {});
    addTearDown(sub.close);
    await repo.setActive(ServiceKind.transmission, 'tr');
    await repo.setActive(ServiceKind.deluge, 'dl');
    await repo.setActive(ServiceKind.qbittorrent, 'qb');
    expect(await settledName(), 'Example qBittorrent ISO');
  });

  test(
    'switching kinds reloads: qBittorrent, Transmission, Deluge and back',
    () async {
      final seen = <String>[];
      final loading = <bool>[];
      final sub = container.listen(torrentListProvider, (_, next) {
        loading.add(next.isLoading);
        if (!next.isLoading && !next.hasError && next.value is TorrentsData) {
          seen.add((next.value! as TorrentsData).torrents.single.name);
        }
      });
      addTearDown(sub.close);
      for (final (k, id) in [
        (ServiceKind.qbittorrent, 'qb'),
        (ServiceKind.transmission, 'tr'),
        (ServiceKind.deluge, 'dl'),
        (ServiceKind.qbittorrent, 'qb'),
      ]) {
        await select(k, id);
        final name = await settledName();
        expect(name, switch (k) {
          ServiceKind.qbittorrent => 'Example qBittorrent ISO',
          ServiceKind.transmission => 'Example Transmission ISO',
          _ => 'Example Deluge ISO',
        });
      }
      // It went through a real reload, and the previous server's data was never
      // reported as the new one's.
      expect(loading, contains(true));
      expect(seen.toSet(), {
        'Example qBittorrent ISO',
        'Example Transmission ISO',
        'Example Deluge ISO',
      });
    },
  );

  test(
    'Deluge: no label plugin, no alternative speed; qBittorrent has both',
    () async {
      final sub = container.listen(torrentCapabilitiesProvider, (_, _) {});
      addTearDown(sub.close);
      await select(ServiceKind.deluge, 'dl');
      await settledName();
      var caps = container.read(torrentCapabilitiesProvider);
      expect(caps.alternativeSpeed, isFalse);
      expect(caps.hasLabel, isFalse);
      await select(ServiceKind.qbittorrent, 'qb');
      await settledName();
      caps = container.read(torrentCapabilitiesProvider);
      expect(caps.alternativeSpeed, isTrue);
      expect(caps.tags, isTrue);
    },
  );

  test(
    'a selection for a kind without a server falls back to the registry',
    () async {
      final sub = container.listen(torrentListProvider, (_, _) {});
      addTearDown(sub.close);
      await repo.setActive(ServiceKind.qbittorrent, 'qb');
      await db
          .into(db.appStateRows)
          .insertOnConflictUpdate(
            AppStateRowsCompanion.insert(
              key: 'torrents.selected_kind',
              value: 'deluge',
            ),
          );
      expect(await settledName(), 'Example qBittorrent ISO');
    },
  );
}
