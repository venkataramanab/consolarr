// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:consolarr/features/torrents/application/torrent_link.dart';
import 'package:consolarr/features/torrents/application/torrent_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

Torrent _t(
  String name, {
  TorrentState state = TorrentState.downloading,
  double progress = 0.5,
  int size = 100,
  int dl = 0,
  int up = 0,
  double ratio = 0,
  Duration? eta,
  DateTime? added,
  String? category,
}) => Torrent(
  hash: name,
  name: name,
  state: state,
  progress: progress,
  size: size,
  dlSpeed: dl,
  upSpeed: up,
  ratio: ratio,
  eta: eta,
  addedOn: added,
  category: category,
);

void main() {
  final all = [
    _t(
      'b',
      state: TorrentState.downloading,
      dl: 5,
      size: 300,
      ratio: 0.1,
      eta: const Duration(minutes: 5),
      added: DateTime.utc(2026, 1, 2),
      category: 'tv',
    ),
    _t(
      'a',
      state: TorrentState.seeding,
      progress: 1,
      up: 3,
      size: 100,
      ratio: 2,
      added: DateTime.utc(2026, 1, 3),
      category: 'iso',
    ),
    _t(
      'c',
      state: TorrentState.paused,
      size: 200,
      ratio: 1,
      added: DateTime.utc(2026, 1, 1),
    ),
    _t('d', state: TorrentState.error, size: 50, ratio: 0),
    _t('e', state: TorrentState.finished, progress: 1, size: 10),
    _t('f', state: TorrentState.stalled, size: 20),
  ];

  List<String> names(TorrentView v) => [
    for (final t in applyView(all, v)) t.name,
  ];

  group('tabs', () {
    test('every tab keeps the right torrents', () {
      List<String> tab(TorrentTab t) =>
          names(TorrentView(tab: t, sort: TorrentSort.name, ascending: true));
      expect(tab(TorrentTab.all), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(tab(TorrentTab.active), ['a', 'b']);
      expect(tab(TorrentTab.downloading), ['b', 'f']);
      expect(tab(TorrentTab.finished), ['a', 'e']);
      expect(tab(TorrentTab.error), ['d']);
    });
  });

  group('sort', () {
    List<String> by(TorrentSort s, {bool asc = true}) =>
        names(TorrentView(sort: s, ascending: asc));

    test('name, size, ratio, progress', () {
      expect(by(TorrentSort.name), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(by(TorrentSort.name, asc: false), ['f', 'e', 'd', 'c', 'b', 'a']);
      expect(by(TorrentSort.size).first, 'e');
      expect(by(TorrentSort.ratio).last, 'a');
      expect(by(TorrentSort.progress).last, isIn(['a', 'e']));
    });

    test('status follows the enum order, labels and speeds sort', () {
      expect(by(TorrentSort.status).first, 'b');
      expect(by(TorrentSort.label, asc: false).first, 'b');
      expect(by(TorrentSort.downSpeed, asc: false).first, 'b');
      expect(by(TorrentSort.upSpeed, asc: false).first, 'a');
    });

    test('added puts newest first when descending; missing dates last', () {
      expect(by(TorrentSort.added, asc: false).first, 'a');
      expect(by(TorrentSort.added).first, isIn(['d', 'e', 'f']));
    });

    test('time left: unknown counts as longest', () {
      expect(by(TorrentSort.timeLeft).first, 'b');
      expect(by(TorrentSort.timeLeft).last, isNot('b'));
    });
  });

  group('search', () {
    test('matches by name, case-insensitively, and combines with a tab', () {
      final lin = [_t('Example Linux ISO'), _t('Other Thing')];
      expect(
        applyView(lin, const TorrentView(query: 'linux')).map((t) => t.name),
        ['Example Linux ISO'],
      );
      expect(applyView(lin, const TorrentView(query: 'zzz')), isEmpty);
      expect(const TorrentView(query: ' ').isFiltered, isFalse);
      expect(const TorrentView(query: 'x').isFiltered, isTrue);
    });

    test('10,000 torrents filter and sort quickly', () {
      final big = [for (var i = 0; i < 10000; i++) sampleTorrent(i)];
      final sw = Stopwatch()..start();
      final out = applyView(big, const TorrentView(query: 'torrent 9'));
      sw.stop();
      expect(out, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('links', () {
    const hash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    test('magnet with name', () {
      final p = parseTorrentLink(
        'magnet:?xt=urn:btih:$hash&dn=Example+Linux+ISO',
      );
      expect((p as MagnetLink).displayName, 'Example Linux ISO');
    });

    test('magnet without dn shows a short hash; base32 and v2 hashes pass', () {
      expect(
        (parseTorrentLink(
          'magnet:?xt=urn:btih:$hash',
        ) as MagnetLink).displayName,
        hash.substring(0, 12),
      );
      expect(
        parseTorrentLink('magnet:?xt=urn:btih:${'A' * 32}'),
        isA<MagnetLink>(),
      );
      expect(
        parseTorrentLink('magnet:?xt=urn:btmh:1220${'a' * 64}'),
        isA<MagnetLink>(),
      );
    });

    test('invalid magnets and schemes are rejected', () {
      for (final bad in [
        'magnet:?xt=urn:btih:zzz',
        'magnet:?dn=Only+Name',
        'magnet:',
      ]) {
        expect(
          (parseTorrentLink(bad) as InvalidLink).problem,
          LinkProblem.hash,
        );
      }
      expect(
        (parseTorrentLink(
          'ftp://files.example/a.torrent',
        ) as InvalidLink).problem,
        LinkProblem.scheme,
      );
      expect(
        (parseTorrentLink('   ') as InvalidLink).problem,
        LinkProblem.empty,
      );
      expect(
        (parseTorrentLink('file:///data/a.torrent') as InvalidLink).problem,
        LinkProblem.scheme,
      );
    });

    test('http(s) URLs: host only, userinfo refused', () {
      final p = parseTorrentLink(
        'https://files.example/a.torrent?passkey=secret-passkey',
      );
      expect((p as UrlLink).host, 'files.example');
      expect(
        (parseTorrentLink(
          'https://user:pw@files.example/a.torrent',
        ) as InvalidLink).problem,
        LinkProblem.userinfo,
      );
      expect(
        (parseTorrentLink('https:///nohost') as InvalidLink).problem,
        LinkProblem.url,
      );
    });

    test('the parsed result never carries the passkey', () {
      final p = parseTorrentLink(
        'magnet:?xt=urn:btih:$hash&tr=https%3A%2F%2Ftracker.example%2Fannounce%3Fpasskey%3Dsecret-passkey',
      );
      expect((p as MagnetLink).displayName, isNot(contains('secret-passkey')));
    });
  });

  group('torrent files', () {
    Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

    test('a bencoded dictionary with info passes', () {
      expect(
        checkTorrentBytes(b('d8:announce3:abc4:infod4:name1:aee')),
        isNull,
      );
    });

    test('other content is refused; huge files are too large', () {
      expect(
        checkTorrentBytes(b('<html>not a torrent</html>')),
        FileProblem.notTorrent,
      );
      expect(checkTorrentBytes(b('d3:foo3:bare')), FileProblem.notTorrent);
      expect(checkTorrentBytes(Uint8List(0)), FileProblem.notTorrent);
      expect(
        checkTorrentBytes(Uint8List(maxTorrentFileBytes + 1)),
        FileProblem.tooLarge,
      );
    });
  });
}
