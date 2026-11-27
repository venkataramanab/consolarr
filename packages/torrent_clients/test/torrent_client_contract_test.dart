// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

Future<T> _inline<T>(T Function() work) async => work();

typedef _Make = (TorrentClient, FakeServer) Function();

(TorrentClient, FakeServer) _qb(String version) {
  final s = FakeQBittorrent(version: version);
  return (
    QBittorrentClient(
      dio: dioWith(s.adapter),
      username: 'test-user',
      password: 'test-password',
      parseRunner: _inline,
    ),
    s,
  );
}

(TorrentClient, FakeServer) _tr() {
  final s = FakeTransmission();
  return (
    TransmissionClient(
      dio: dioWith(s.adapter, base: 'https://transmission.example'),
      username: 'test-user',
      password: 'test-password',
      parseRunner: _inline,
    ),
    s,
  );
}

(TorrentClient, FakeServer) _dl() {
  final s = FakeDeluge();
  return (
    DelugeClient(
      dio: dioWith(s.adapter, base: 'https://deluge.example'),
      password: 'test-password',
      parseRunner: _inline,
    ),
    s,
  );
}

/// The same suite against every client and its fake server.
void main() {
  final makers = <String, _Make>{
    'qBittorrent v4': () => _qb('v4.6.3'),
    'qBittorrent v5': () => _qb('v5.0.1'),
    'Transmission': _tr,
    'Deluge': _dl,
  };
  makers.forEach((name, make) {
    group('contract: $name', () {
      late TorrentClient client;
      late FakeServer server;
      setUp(() => (client, server) = make());

      test('version and list', () async {
        expect((await client.fetchVersion()).isOk, isTrue);
        final list = (await client.listTorrents()).valueOrNull!;
        expect(list, hasLength(1));
        expect(list.single.name, 'Example Linux ISO');
        expect(list.single.state, TorrentState.downloading);
        expect(list.single.progress, closeTo(0.5, 0.001));
        expect((await client.transferInfo()).valueOrNull!.dlSpeed, 100);
      });

      test('pause then resume', () async {
        expect((await client.pause([exampleHash])).isOk, isTrue);
        var t = (await client.listTorrents()).valueOrNull!.single;
        expect(t.state, TorrentState.paused);
        expect((await client.resume([exampleHash])).isOk, isTrue);
        t = (await client.listTorrents()).valueOrNull!.single;
        expect(t.state, TorrentState.downloading);
      });

      for (final withData in [false, true]) {
        test('delete sends deleteData=$withData', () async {
          expect(
            (await client.delete([exampleHash], deleteFiles: withData)).isOk,
            isTrue,
          );
          expect(server.lastDeleteData, withData);
          expect((await client.listTorrents()).valueOrNull, isEmpty);
        });
      }

      test('add magnet with options', () async {
        const options = AddTorrentOptions(
          savePath: '/data/example',
          paused: true,
        );
        final r = await client.addMagnetOrUrl(exampleMagnet, options: options);
        expect(r.isOk, isTrue, reason: '${r.errorOrNull?.category}');
        expect(server.addCalls, 1);
        expect(server.lastSavePath, '/data/example');
        expect(server.lastAddPaused, isTrue);
        expect((await client.listTorrents()).valueOrNull, hasLength(2));
      });

      test('add url and file', () async {
        expect(
          (await client.addMagnetOrUrl('https://files.example/a.torrent')).isOk,
          isTrue,
        );
        final bytes = Uint8List.fromList('d4:infod4:name3:abcee'.codeUnits);
        final r = await client.addFile(bytes, fileName: 'a.torrent');
        expect(r.isOk, isTrue, reason: '${r.errorOrNull?.category}');
        expect(server.addCalls, 2);
      });

      test('limits round trip, including unlimited', () async {
        expect(
          (await client.setGlobalLimits(
            const GlobalLimits(download: 2048000, upload: 512000),
          )).isOk,
          isTrue,
        );
        var l = (await client.globalLimits()).valueOrNull!;
        expect(l.download, 2048000);
        expect(l.upload, 512000);
        expect(
          (await client.setGlobalLimits(
            const GlobalLimits(download: 0, upload: 0),
          )).isOk,
          isTrue,
        );
        l = (await client.globalLimits()).valueOrNull!;
        expect(l.download, 0);
        expect(l.upload, 0);
      });

      test('limits that are not a multiple of the unit round up', () async {
        // 1 MiB: exact for byte and KiB based servers, rounded up to whole
        // kB (1000 bytes) on Transmission.
        await client.setGlobalLimits(
          const GlobalLimits(download: 1048576, upload: 1),
        );
        final l = (await client.globalLimits()).valueOrNull!;
        final unit = client.capabilities.speedLimitUnit;
        switch (client.kind) {
          case ServiceKind.transmission:
            expect(unit, 1000);
            expect(l.download, 1049000);
            expect(l.upload, 1000);
          case ServiceKind.deluge:
            expect(unit, 1024);
            expect(l.download, 1048576);
          case ServiceKind.qbittorrent:
            expect(unit, 1);
            expect(l.download, 1048576);
            expect(l.upload, 1);
          default:
            fail('unexpected kind');
        }
      });

      test('detail has counts, path and transferred', () async {
        final d = (await client.torrentDetail(exampleHash)).valueOrNull!;
        expect(d.savePath, '/downloads/example');
        expect(d.seeds, isNotNull);
        expect(d.peers, isNotNull);
        expect(d.downloaded, 500);
        expect(d.uploaded, 250);
        expect(d.torrent.name, 'Example Linux ISO');
      });

      test('detail of an unknown torrent is not_found', () async {
        final r = await client.torrentDetail('f' * 40);
        expect(r.errorOrNull?.category, ErrorCategory.notFound);
      });

      test('capabilities match the matrix', () async {
        await client.listTorrents();
        final c = client.capabilities;
        switch (client.kind) {
          case ServiceKind.qbittorrent:
            expect(c.alternativeSpeed, isTrue);
            expect(c.tags, isTrue);
            expect(c.labelModel, LabelModel.category);
          case ServiceKind.transmission:
            expect(c.alternativeSpeed, isTrue);
            expect(c.labelModel, LabelModel.none);
          case ServiceKind.deluge:
            expect(c.alternativeSpeed, isFalse);
            expect(c.tags, isFalse);
            expect(c.labelModel, LabelModel.label);
          default:
            fail('unexpected kind');
        }
      });

      test('alternative speed toggle', () async {
        final r = await client.setAlternativeSpeed(true);
        if (client.capabilities.alternativeSpeed) {
          expect(r.isOk, isTrue);
          expect(
            (await client.globalLimits()).valueOrNull!.alternativeActive,
            isTrue,
          );
          expect(server.alt, isTrue);
        } else {
          expect(r.errorOrNull, isA<UnsupportedAction>());
        }
      });
    });
  });
}
