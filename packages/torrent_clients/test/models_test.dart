// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

Map<String, Object?> fullTorrent([int i = 1]) => {
  'hash': 'a' * 40,
  'name': 'Example Torrent $i',
  'state': 'downloading',
  'progress': 0.25,
  'size': 1000000,
  'dlspeed': 2048,
  'upspeed': 512,
  'eta': 3600,
  'ratio': 1.5,
  'added_on': 1700000000,
  'category': 'tv',
  'magnet_uri': 'ignored',
  'save_path': '/ignored',
  'future_field': [1, 2],
};

void main() {
  group('Torrent.fromJson', () {
    test('parses a full record', () {
      final t = Torrent.fromJson(fullTorrent());
      expect(t.hash, 'a' * 40);
      expect(t.name, 'Example Torrent 1');
      expect(t.state, TorrentState.downloading);
      expect(t.progress, 0.25);
      expect(t.size, 1000000);
      expect(t.dlSpeed, 2048);
      expect(t.upSpeed, 512);
      expect(t.eta, const Duration(hours: 1));
      expect(t.ratio, 1.5);
      expect(
        t.addedOn,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
      );
      expect(t.category, 'tv');
    });

    test('eta of 8640000 (infinity) is null; negative is null', () {
      expect(Torrent.fromJson({...fullTorrent(), 'eta': 8640000}).eta, isNull);
      expect(Torrent.fromJson({...fullTorrent(), 'eta': -1}).eta, isNull);
    });

    test('progress is clamped to 0..1; empty category is null', () {
      expect(Torrent.fromJson({...fullTorrent(), 'progress': 1.7}).progress, 1);
      expect(Torrent.fromJson({...fullTorrent(), 'progress': -2}).progress, 0);
      expect(
        Torrent.fromJson({...fullTorrent(), 'category': ''}).category,
        isNull,
      );
    });

    test('tolerates a minimal record', () {
      final t = Torrent.fromJson({'hash': 'h', 'name': 'n'});
      expect(t.state, TorrentState.unknown);
      expect(t.size, 0);
      expect(t.eta, isNull);
      expect(t.addedOn, isNull);
    });

    test('wrong types for required fields are FormatException', () {
      for (final bad in <Map<String, Object?>>[
        {'hash': 1, 'name': 'n'},
        {'hash': 'h', 'name': null},
        {'name': 'n'},
      ]) {
        expect(() => Torrent.fromJson(bad), throwsFormatException);
      }
    });

    test('toString omits the name', () {
      expect('${Torrent.fromJson(fullTorrent())}', isNot(contains('Example')));
    });
  });

  group('parseTorrentList / parseTransferInfo', () {
    test('parse arrays and objects', () {
      expect(
        parseTorrentList(jsonEncode([fullTorrent(), fullTorrent(2)])).items,
        hasLength(2),
      );
      final mixed = parseTorrentList(
        jsonEncode([
          fullTorrent(),
          'junk',
          {'hash': 1},
          fullTorrent(2),
        ]),
      );
      expect(mixed.items, hasLength(2));
      expect(mixed.skipped, 2);
      final t = parseTransferInfo(
        jsonEncode({
          'dl_info_speed': 100,
          'up_info_speed': 50,
          'dl_info_data': 1000,
          'up_info_data': 500,
          'connection_status': 'connected',
          'dht_nodes': 3,
        }),
      );
      expect(t.dlSpeed, 100);
      expect(t.upSpeed, 50);
      expect(t.dlTotal, 1000);
      expect(t.upTotal, 500);
      expect(t.connectionStatus, 'connected');
    });

    test('shape errors are FormatException', () {
      expect(() => parseTorrentList('{}'), throwsFormatException);
      expect(() => parseTorrentList('[1]'), throwsFormatException);
      expect(() => parseTorrentList('x'), throwsFormatException);
      expect(() => parseTransferInfo('[]'), throwsFormatException);
    });

    test('transfer info tolerates missing fields', () {
      final t = parseTransferInfo('{}');
      expect(t.dlSpeed, 0);
      expect(t.connectionStatus, isNull);
    });
  });
}
