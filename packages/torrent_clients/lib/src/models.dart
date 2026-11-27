// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:core/core.dart';

/// How a torrent is doing, reduced to what the UI conveys (icon + text).
enum TorrentState {
  downloading,
  stalled,
  checking,
  queued,
  seeding,
  paused,
  finished,
  error,
  unknown;

  /// Maps a qBittorrent WebUI state string (including the v5 `stopped*`
  /// names). Paused or stopped torrents at 100% are [finished].
  static TorrentState fromQBittorrent(String? raw, {required double progress}) {
    switch (raw) {
      case 'error':
      case 'missingFiles':
        return error;
      case 'uploading':
      case 'forcedUP':
      case 'stalledUP':
        return seeding;
      case 'queuedUP':
      case 'queuedDL':
        return queued;
      case 'checkingUP':
      case 'checkingDL':
      case 'checkingResumeData':
      case 'allocating':
      case 'moving':
        return checking;
      case 'downloading':
      case 'metaDL':
      case 'forcedMetaDL':
      case 'forcedDL':
        return downloading;
      case 'stalledDL':
        return stalled;
      case 'pausedDL':
      case 'pausedUP':
      case 'stoppedDL':
      case 'stoppedUP':
        return progress >= 1 ? finished : paused;
      default:
        return unknown;
    }
  }

  /// Maps Transmission's numeric `status` (0 stopped, 1 check wait, 2
  /// checking, 3 download wait, 4 downloading, 5 seed wait, 6 seeding).
  ///
  /// A torrent with a non-zero `error` is [error] whatever its status; a
  /// stopped torrent at 100% is [finished]; a downloading torrent that has no
  /// peers sending data is [stalled].
  static TorrentState fromTransmission(
    int? status, {
    required double progress,
    bool hasError = false,
    bool receiving = true,
  }) {
    if (hasError) return error;
    switch (status) {
      case 0:
        return progress >= 1 ? finished : paused;
      case 1:
      case 2:
        return checking;
      case 3:
      case 5:
        return queued;
      case 4:
        return receiving ? downloading : stalled;
      case 6:
        return seeding;
      default:
        return unknown;
    }
  }

  /// Maps a Deluge `state` string (`Downloading`, `Seeding`, `Paused`,
  /// `Checking`, `Queued`, `Error`, `Moving`, `Allocating`).
  ///
  /// Paused at 100% is [finished]; downloading without payload is [stalled].
  static TorrentState fromDeluge(
    String? raw, {
    required double progress,
    bool receiving = true,
  }) {
    switch (raw) {
      case 'Error':
        return error;
      case 'Downloading':
        return receiving ? downloading : stalled;
      case 'Seeding':
        return seeding;
      case 'Queued':
        return queued;
      case 'Checking':
      case 'Allocating':
      case 'Moving':
        return checking;
      case 'Paused':
        return progress >= 1 ? finished : paused;
      default:
        return unknown;
    }
  }
}

/// One torrent. [name] is server-supplied plain text.
class Torrent {
  const Torrent({
    required this.hash,
    required this.name,
    required this.state,
    required this.progress,
    required this.size,
    required this.dlSpeed,
    required this.upSpeed,
    required this.ratio,
    this.eta,
    this.addedOn,
    this.category,
    this.label,
  });

  /// Throws [FormatException] when `hash` or `name` is missing or mistyped;
  /// everything else is optional.
  factory Torrent.fromJson(Map<String, Object?> json) {
    final hash = json['hash'];
    final name = json['name'];
    if (hash is! String) throw const FormatException('hash must be a string');
    if (name is! String) throw const FormatException('name must be a string');
    final progress = jsonNum(json['progress']).toDouble().clamp(0.0, 1.0);
    final eta = jsonNum(json['eta']).toInt();
    final added = jsonNum(json['added_on']).toInt();
    final category = json['category'];
    return Torrent(
      hash: hash,
      name: name,
      state: TorrentState.fromQBittorrent(
        json['state'] is String ? json['state']! as String : null,
        progress: progress,
      ),
      progress: progress,
      size: jsonNum(json['size']).toInt(),
      dlSpeed: jsonNum(json['dlspeed']).toInt(),
      upSpeed: jsonNum(json['upspeed']).toInt(),
      ratio: jsonNum(json['ratio']).toDouble(),
      // qBittorrent reports 8640000 s (100 days) for "infinity".
      eta: eta > 0 && eta < qbInfiniteEta ? Duration(seconds: eta) : null,
      addedOn: added > 0
          ? DateTime.fromMillisecondsSinceEpoch(added * 1000, isUtc: true)
          : null,
      category: category is String && category.isNotEmpty ? category : null,
    );
  }

  /// qBittorrent's sentinel for an unknown ETA, in seconds.
  static const qbInfiniteEta = 8640000;

  final String hash;
  final String name;
  final TorrentState state;

  /// 0..1.
  final double progress;

  /// Bytes.
  final int size;

  /// Bytes per second.
  final int dlSpeed;
  final int upSpeed;
  final double ratio;
  final Duration? eta;
  final DateTime? addedOn;
  final String? category;

  /// A secondary label (Transmission's first label); plain text.
  final String? label;

  /// Omits the name so logs never carry media titles.
  @override
  String toString() => 'Torrent(${state.name})';
}

/// Global transfer statistics (`transfer/info`).
class TransferInfo {
  const TransferInfo({
    required this.dlSpeed,
    required this.upSpeed,
    required this.dlTotal,
    required this.upTotal,
    this.connectionStatus,
  });

  /// Bytes per second.
  final int dlSpeed;
  final int upSpeed;

  /// Bytes transferred this session.
  final int dlTotal;
  final int upTotal;

  /// `connected`, `firewalled` or `disconnected` (plain text from the server).
  final String? connectionStatus;
}

num jsonNum(Object? v) => v is num && v.isFinite ? v : 0;

Map<String, Object?> jsonObject(Object? v) {
  if (v is! Map) throw const FormatException('expected an object');
  return {
    for (final e in v.entries)
      if (e.key is String) e.key as String: e.value,
  };
}

/// Parses a `torrents/info` body. Top level so it can run in an isolate.
ParsedRows<Torrent> parseTorrentList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) throw const FormatException('expected a JSON array');
  return parseRowsTolerant(decoded, (e) => Torrent.fromJson(jsonObject(e)));
}

/// Parses a `transfer/info` body.
TransferInfo parseTransferInfo(String body) {
  final m = jsonObject(jsonDecode(body));
  final status = m['connection_status'];
  return TransferInfo(
    dlSpeed: jsonNum(m['dl_info_speed']).toInt(),
    upSpeed: jsonNum(m['up_info_speed']).toInt(),
    dlTotal: jsonNum(m['dl_info_data']).toInt(),
    upTotal: jsonNum(m['up_info_data']).toInt(),
    connectionStatus: status is String ? status : null,
  );
}
