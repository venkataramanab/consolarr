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

/// [path] with every symbolic link resolved. A file that is already gone is
/// resolved through its directory, so the empty directories it left can still
/// be tidied. Throws when nothing along the way exists.
String _resolve(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final dir = Directory(p.dirname(path)).resolveSymbolicLinksSync();
    return p.join(dir, p.basename(path));
  }
  return File(path).resolveSymbolicLinksSync();
}

/// Deletes the picker's private copy of a document: the file itself, then
/// its directories (`<cache>/<uuid>/`) from the inside out, each only when it
/// is empty. Nothing else in a directory is ever deleted (no recursive
/// delete: a directory that holds anything besides our copy stays). A path
/// outside the app cache (a real user file, for example from a platform whose
/// picker returns the original) is never touched. Returns whether anything
/// was deleted; never throws.
Future<bool> deleteCachedPickerCopy(String path, String cacheDir) async {
  try {
    if (path.isEmpty) return false;
    // Resolve symbolic links on both sides first: a link inside the cache
    // that points elsewhere must not let the check pass for a file outside.
    // A path that cannot be resolved (it is gone) has nothing to delete.
    final cache = p.normalize(
      p.absolute(Directory(cacheDir).resolveSymbolicLinksSync()),
    );
    final file = p.normalize(p.absolute(_resolve(path)));
    if (!p.isWithin(cache, file)) return false;
    var deleted = false;
    final f = File(file);
    if (f.existsSync()) {
      await f.delete();
      deleted = true;
    }
    var dir = p.dirname(file);
    // Strictly inside the cache: the cache directory itself is never removed.
    while (p.isWithin(cache, dir)) {
      final d = Directory(dir);
      if (!d.existsSync() || d.listSync().isNotEmpty) break;
      await d.delete();
      deleted = true;
      dir = p.dirname(dir);
    }
    return deleted;
  } on Object {
    return false;
  }
}
