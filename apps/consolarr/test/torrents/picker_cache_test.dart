// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/data/system_file_picker.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

List<int> _torrentBytes() => 'd4:infod4:name3:abcee'.codeUnits;

void main() {
  group('deleteCachedPickerCopy', () {
    late Directory cache;
    setUp(() => cache = Directory.systemTemp.createTempSync('picker_cache'));
    tearDown(() => cache.deleteSync(recursive: true));

    test('removes the picker uuid directory inside the cache', () async {
      final dir = Directory(p.join(cache.path, 'uuid-1'))..createSync();
      final file = File(p.join(dir.path, 'a.torrent'))..writeAsStringSync('x');
      expect(await deleteCachedPickerCopy(file.path, cache.path), isTrue);
      expect(dir.existsSync(), isFalse);
      expect(cache.existsSync(), isTrue);
    });

    test(
      'T4: only the file goes; its directory goes only when empty',
      () async {
        final dir = Directory(p.join(cache.path, 'uuid-2'))..createSync();
        final file = File(p.join(dir.path, 'a.torrent'))
          ..writeAsStringSync('x');
        final other = File(p.join(dir.path, 'other.txt'))
          ..writeAsStringSync('y');
        expect(await deleteCachedPickerCopy(file.path, cache.path), isTrue);
        expect(file.existsSync(), isFalse);
        // Something else lives there: it is not ours to delete.
        expect(other.existsSync(), isTrue);
        expect(dir.existsSync(), isTrue);
        other.deleteSync();
        // Nothing is left: a second discard tidies the empty directory.
        expect(await deleteCachedPickerCopy(file.path, cache.path), isTrue);
        expect(dir.existsSync(), isFalse);
        expect(cache.existsSync(), isTrue);
      },
    );

    test('T4: nested content below the picker directory is kept', () async {
      final dir = Directory(p.join(cache.path, 'uuid-3', 'sub'))
        ..createSync(recursive: true);
      final keep = File(p.join(dir.path, 'keep.bin'))..writeAsStringSync('z');
      final file = File(p.join(cache.path, 'uuid-3', 'a.torrent'))
        ..writeAsStringSync('x');
      await deleteCachedPickerCopy(file.path, cache.path);
      expect(file.existsSync(), isFalse);
      expect(keep.existsSync(), isTrue);
    });

    test('a file directly in the cache: only the file goes', () async {
      final file = File(p.join(cache.path, 'a.torrent'))
        ..writeAsStringSync('x');
      expect(await deleteCachedPickerCopy(file.path, cache.path), isTrue);
      expect(file.existsSync(), isFalse);
      expect(cache.existsSync(), isTrue);
    });

    test('never touches a file outside the cache', () async {
      final other = Directory.systemTemp.createTempSync('user_files');
      addTearDown(() => other.deleteSync(recursive: true));
      final file = File(p.join(other.path, 'mine.torrent'))
        ..writeAsStringSync('x');
      expect(await deleteCachedPickerCopy(file.path, cache.path), isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('path traversal out of the cache is refused', () async {
      final other = Directory.systemTemp.createTempSync('user_files');
      addTearDown(() => other.deleteSync(recursive: true));
      final file = File(p.join(other.path, 'mine.torrent'))
        ..writeAsStringSync('x');
      final sneaky = p.join(
        cache.path,
        'uuid',
        '..',
        '..',
        p.relative(file.path, from: p.dirname(cache.path)),
      );
      expect(await deleteCachedPickerCopy(sneaky, cache.path), isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('the cache directory itself and empty input are safe', () async {
      expect(await deleteCachedPickerCopy(cache.path, cache.path), isFalse);
      expect(await deleteCachedPickerCopy('', cache.path), isFalse);
      expect(cache.existsSync(), isTrue);
    });

    test('a missing file is not an error', () async {
      expect(
        await deleteCachedPickerCopy(p.join(cache.path, 'u', 'x'), cache.path),
        isFalse,
      );
    });
  });

  group('AddTorrentController.addFiles', () {
    late List<String> discarded;

    PickedTorrentFile file(String name, {List<int>? bytes, int? length}) {
      final data = bytes ?? _torrentBytes();
      return PickedTorrentFile(
        name: name,
        length: () async => length ?? data.length,
        readBytes: () async => Uint8List.fromList(data),
        discard: () async => discarded.add(name),
      );
    }

    ProviderContainer container(FakeTorrentClient client) {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          testDatabaseOverride,
          torrentClientProvider.overrideWith((ref) async => client),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      addTearDown(c.dispose);
      c.listen(addTorrentProvider, (_, _) {});
      return c;
    }

    setUp(() => discarded = []);

    test(
      'every cached copy is discarded after reading, whatever happens',
      () async {
        final client = FakeTorrentClient();
        final c = container(client);
        await c.read(addTorrentProvider.notifier).addFiles([
          file('ok.torrent'),
          file('big.torrent', length: 6 * 1024 * 1024),
          file('junk.torrent', bytes: [1, 2, 3]),
        ], const AddTorrentOptions());
        expect(discarded, ['ok.torrent', 'big.torrent', 'junk.torrent']);
      },
    );

    test('T8: a pick that arrives while another add runs is discarded, not '
        'leaked', () async {
      final client = FakeTorrentClient()..actionGate = Completer<void>();
      final c = container(client);
      final first = c.read(addTorrentProvider.notifier).addFiles([
        file('first.torrent'),
      ], const AddTorrentOptions());
      await Future<void>.delayed(Duration.zero);
      await c.read(addTorrentProvider.notifier).addFiles([
        file('second.torrent'),
        file('third.torrent'),
      ], const AddTorrentOptions());
      expect(discarded, containsAll(['second.torrent', 'third.torrent']));
      client.actionGate!.complete();
      await first;
    });

    test('T3: disposing the controller mid-batch discards the rest', () async {
      final client = FakeTorrentClient()..actionGate = Completer<void>();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          testDatabaseOverride,
          torrentClientProvider.overrideWith((ref) async => client),
          clockProvider.overrideWithValue(() => fixedNow),
        ],
      );
      final sub = c.listen(addTorrentProvider, (_, _) {});
      final run = c.read(addTorrentProvider.notifier).addFiles([
        file('a.torrent'),
        file('b.torrent'),
        file('c.torrent'),
      ], const AddTorrentOptions());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(discarded, ['a.torrent']);
      sub.close();
      c.dispose();
      client.actionGate!.complete();
      await run;
      expect(discarded, ['a.torrent', 'b.torrent', 'c.torrent']);
    });

    test(
      'a pick above the cap: the extras are discarded unread and counted',
      () async {
        final client = FakeTorrentClient();
        final c = container(client);
        var reads = 0;
        final many = [
          for (var i = 0; i < maxPickedTorrentFiles + 5; i++)
            PickedTorrentFile(
              name: 'f$i.torrent',
              length: () async => _torrentBytes().length,
              readBytes: () async {
                reads++;
                return Uint8List.fromList(_torrentBytes());
              },
              discard: () async => discarded.add('f$i'),
            ),
        ];
        await c
            .read(addTorrentProvider.notifier)
            .addFiles(many, const AddTorrentOptions());
        final state = c.read(addTorrentProvider) as AddFinished;
        expect(state.results, hasLength(maxPickedTorrentFiles));
        expect(state.ignored, 5);
        expect(reads, maxPickedTorrentFiles);
        expect(discarded, hasLength(maxPickedTorrentFiles + 5));
      },
    );
  });
}
