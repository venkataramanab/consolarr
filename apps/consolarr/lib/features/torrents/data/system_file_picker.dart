// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/add_torrent_controller.dart';
import 'package:file_selector/file_selector.dart';

/// Opens the system document picker (Android's storage access framework: no
/// storage permission) for `.torrent` files. Bytes are read lazily, after the
/// size check.
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
      ),
  ];
}
