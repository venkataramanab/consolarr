// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opens the system document picker (Android's storage access framework: no
/// storage permission) for `.torrent` files.
///
/// **What the plugin does first.** On Android `file_selector_android` copies
/// every chosen document into `cacheDir/<uuid>/` and reads it into memory
/// *before* Dart sees the file, so the size cap in the controller runs after
/// that cost has been paid, and the copy (a `.torrent` can carry a tracker
/// passkey) stays on disk until someone deletes it. This function therefore
/// hands out a `discard` callback per file; the controller calls it as soon as
/// the bytes were read (or the file was skipped), which removes the copy.
Future<List<PickedTorrentFile>> pickTorrentFilesFromSystem() async {
  const group = XTypeGroup(
    label: 'torrent',
    extensions: ['torrent'],
    mimeTypes: ['application/x-bittorrent'],
  );
  final files = await openFiles(acceptedTypeGroups: [group]);
  return [
    for (final f in files)
      PickedTorrentFile(
        name: f.name,
        length: f.length,
        readBytes: f.readAsBytes,
        discard: () async {
          final cache = await getTemporaryDirectory();
          await deleteCachedPickerCopy(f.path, cache.path);
        },
      ),
  ];
}

/// Deletes the picker's private copy of a document: the file's directory
/// (`<cache>/<uuid>/`) when it lies strictly inside [cacheDir], or just the
/// file when it sits directly in it. A path outside the app cache (a real
/// user file, for example from a platform whose picker returns the original)
/// is never touched. Returns whether anything was deleted; never throws.
Future<bool> deleteCachedPickerCopy(String path, String cacheDir) async {
  try {
    if (path.isEmpty) return false;
    final cache = p.normalize(p.absolute(cacheDir));
    final file = p.normalize(p.absolute(path));
    if (!p.isWithin(cache, file)) return false;
    final dir = p.dirname(file);
    if (dir != cache && p.isWithin(cache, dir)) {
      // Only the top-level directory under the cache: `<cache>/<uuid>`.
      final top = p.join(cache, p.split(p.relative(file, from: cache)).first);
      final topDir = Directory(top);
      if (!topDir.existsSync()) return false;
      await topDir.delete(recursive: true);
      return true;
    }
    final f = File(file);
    if (!f.existsSync()) return false;
    await f.delete();
    return true;
  } on Object {
    return false;
  }
}
