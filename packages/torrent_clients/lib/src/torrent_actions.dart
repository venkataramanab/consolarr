// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:torrent_clients/src/models.dart';
import 'package:torrent_clients/src/torrent_capabilities.dart';

/// The failure of an action a client does not implement (yet) or that the
/// server version does not offer. Typed so the UI can say "not available for
/// this client" instead of a generic error.
class UnsupportedAction extends AppError {
  const UnsupportedAction(String action)
    : super(
        ErrorCategory.unsupportedVersion,
        debugDetail: 'unsupported action: $action',
      );

  /// Whether [error] is an [UnsupportedAction].
  static bool isIt(AppError error) => error is UnsupportedAction;
}

/// Something that went wrong after a torrent was added successfully.
enum AddWarning {
  /// The torrent was added but the label/category could not be applied.
  labelNotApplied,
}

/// Some, but not all, of the torrents of a bulk action failed. [failed] holds
/// their ids (hashes), [total] the number of torrents the action was for. The
/// error `category` is that of the first failure. When every torrent fails the
/// plain error is returned instead.
class PartialActionFailure extends AppError {
  PartialActionFailure({
    required ErrorCategory category,
    required this.failed,
    required this.total,
  }) : super(category, debugDetail: '${failed.length} of $total failed');

  final List<String> failed;
  final int total;
}

/// Options for adding a torrent. Every field is optional; a client ignores
/// what its server cannot do.
class AddTorrentOptions {
  const AddTorrentOptions({
    this.savePath,
    this.category,
    this.tags = const [],
    this.paused = false,
    this.onWarning,
  });

  final String? savePath;

  /// qBittorrent category or Deluge label.
  final String? category;

  /// qBittorrent tags or Transmission labels.
  final List<String> tags;
  final bool paused;

  /// Called (on success of the add) with a warning the user should see, for
  /// example when the label could not be applied.
  final void Function(AddWarning warning)? onWarning;
}

/// One file inside a torrent.
class TorrentFile {
  const TorrentFile({
    required this.name,
    required this.size,
    required this.progress,
  });

  /// Path relative to the torrent's save path (server-supplied plain text).
  final String name;
  final int size;

  /// 0..1.
  final double progress;
}

/// Everything the detail screen needs beyond the list row.
class TorrentDetail {
  const TorrentDetail({
    required this.torrent,
    this.savePath,
    this.files = const [],
    this.seeds,
    this.seedsTotal,
    this.peers,
    this.peersTotal,
    this.availability,
    this.downloaded,
    this.uploaded,
  });

  final Torrent torrent;
  final String? savePath;
  final List<TorrentFile> files;

  /// Connected seeds, and seeds the trackers know about (`null` = unknown).
  final int? seeds;
  final int? seedsTotal;

  /// Connected peers, and peers the trackers know about.
  final int? peers;
  final int? peersTotal;

  /// Distributed copies (1.0 = one full copy among connected peers); `null`
  /// when the client does not report it.
  final double? availability;

  /// Bytes transferred over the torrent's lifetime.
  final int? downloaded;
  final int? uploaded;
}

/// The global speed limits and the alternative-speed state of a client.
///
/// Limits are bytes per second, `0` means unlimited. [alternativeActive] is
/// `null` when the client has no alternative-speed mode.
class SpeedLimitsState {
  const SpeedLimitsState({
    required this.download,
    required this.upload,
    this.alternativeActive,
  });

  final int download;
  final int upload;
  final bool? alternativeActive;
}

/// Global speed limits in bytes per second; `null` leaves a limit unchanged,
/// `0` means unlimited.
class GlobalLimits {
  const GlobalLimits({this.download, this.upload});

  final int? download;
  final int? upload;
}

/// The actions every torrent client offers. Declared on the interface now so
/// clients and test fakes change once; implementations that do not support an
/// action return an [UnsupportedAction] error (see [UnsupportedTorrentActions]).
abstract interface class TorrentActions {
  /// Pauses (stops) the torrents with these [hashes].
  Future<Result<void>> pause(List<String> hashes);

  /// Resumes (starts) the torrents with these [hashes].
  Future<Result<void>> resume(List<String> hashes);

  /// Removes the torrents; with [deleteFiles] also the downloaded data.
  Future<Result<void>> delete(List<String> hashes, {required bool deleteFiles});

  /// Adds a magnet link or a URL of a `.torrent` file.
  Future<Result<void>> addMagnetOrUrl(
    String link, {
    AddTorrentOptions options = const AddTorrentOptions(),
  });

  /// Adds the contents of a `.torrent` file.
  Future<Result<void>> addFile(
    Uint8List bytes, {
    required String fileName,
    AddTorrentOptions options = const AddTorrentOptions(),
  });

  /// Sets the global download/upload speed limits.
  Future<Result<void>> setGlobalLimits(GlobalLimits limits);

  /// One torrent in detail.
  Future<Result<TorrentDetail>> torrentDetail(String hash);

  /// The current global limits (and whether alternative limits are active).
  Future<Result<SpeedLimitsState>> globalLimits();

  /// Switches the alternative speed limits on or off (only for clients whose
  /// `TorrentCapabilities.alternativeSpeed` is true).
  Future<Result<void>> setAlternativeSpeed(bool enabled);
}

/// Default implementations that answer every action with [UnsupportedAction].
///
/// Mix this into a client (or a test fake) and override only what it
/// supports; when an action is added to [TorrentActions] such classes keep
/// compiling.
mixin UnsupportedTorrentActions implements TorrentActions {
  /// A client built on this mixin supports no optional control until it
  /// overrides this (it satisfies `TorrentClient.capabilities`).
  TorrentCapabilities get capabilities => const TorrentCapabilities();

  Result<T> _unsupported<T>(String action) =>
      Result.err(UnsupportedAction(action));

  @override
  Future<Result<void>> pause(List<String> hashes) async =>
      _unsupported('pause');

  @override
  Future<Result<void>> resume(List<String> hashes) async =>
      _unsupported('resume');

  @override
  Future<Result<void>> delete(
    List<String> hashes, {
    required bool deleteFiles,
  }) async => _unsupported('delete');

  @override
  Future<Result<void>> addMagnetOrUrl(
    String link, {
    AddTorrentOptions options = const AddTorrentOptions(),
  }) async => _unsupported('addMagnetOrUrl');

  @override
  Future<Result<void>> addFile(
    Uint8List bytes, {
    required String fileName,
    AddTorrentOptions options = const AddTorrentOptions(),
  }) async => _unsupported('addFile');

  @override
  Future<Result<void>> setGlobalLimits(GlobalLimits limits) async =>
      _unsupported('setGlobalLimits');

  @override
  Future<Result<TorrentDetail>> torrentDetail(String hash) async =>
      _unsupported('torrentDetail');

  @override
  Future<Result<SpeedLimitsState>> globalLimits() async =>
      _unsupported('globalLimits');

  @override
  Future<Result<void>> setAlternativeSpeed(bool enabled) async =>
      _unsupported('setAlternativeSpeed');
}
