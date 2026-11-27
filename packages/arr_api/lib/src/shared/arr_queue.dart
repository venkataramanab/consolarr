// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/json_read.dart';

/// What a queue item is doing, derived from the several status fields the
/// servers report. Shown as an icon and text, never colour alone.
enum ArrQueueState {
  downloading,
  paused,
  queued,
  delayed,
  importPending,
  importing,
  importFailed,
  downloadFailed,
  clientUnavailable,
  warning,
  completed,
  unknown,
}

/// Which download protocol a queue item or release uses.
enum ArrProtocol { torrent, usenet, unknown }

ArrProtocol parseArrProtocol(String? v) => switch (v?.toLowerCase()) {
  'torrent' => ArrProtocol.torrent,
  'usenet' => ArrProtocol.usenet,
  _ => ArrProtocol.unknown,
};

/// A queue message group (`statusMessages[]`): a title and its lines. Plain
/// text from the server.
class ArrStatusMessage {
  const ArrStatusMessage({this.title, this.messages = const []});

  factory ArrStatusMessage.fromJson(Map<String, Object?> json) =>
      ArrStatusMessage(
        title: JsonRead.string(json, 'title'),
        messages: [
          for (final m in JsonRead.list(json, 'messages'))
            if (m is String && m.isNotEmpty) m,
        ],
      );

  final String? title;
  final List<String> messages;

  Map<String, Object?> toJson() => {'title': title, 'messages': messages};

  @override
  bool operator ==(Object other) =>
      other is ArrStatusMessage &&
      other.title == title &&
      other.messages.length == messages.length &&
      [
        for (var i = 0; i < messages.length; i++)
          other.messages[i] == messages[i],
      ].every((e) => e);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(messages));
}

/// One entry of `GET /queue` (Sonarr and Radarr share the shape).
///
/// Release and media titles are server text: render as plain text only, never
/// log or report them.
class ArrQueueItem {
  const ArrQueueItem({
    required this.id,
    required this.title,
    this.state = ArrQueueState.unknown,
    this.size = 0,
    this.sizeLeft = 0,
    this.timeLeft,
    this.estimatedCompletion,
    this.protocol = ArrProtocol.unknown,
    this.downloadClient,
    this.indexer,
    this.qualityName,
    this.added,
    this.messages = const [],
    this.errorMessage,
    this.seriesId,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.movieId,
    this.mediaTitle,
    this.episodeTitle,
    this.downloadId,
  });

  factory ArrQueueItem.fromJson(Map<String, Object?> json) {
    final size = _num(json, 'size');
    final left = _num(json, 'sizeleft');
    final series = JsonRead.map(json['series']);
    final movie = JsonRead.map(json['movie']);
    final episode = JsonRead.map(json['episode']);
    final quality = JsonRead.map(JsonRead.map(json['quality'])?['quality']);
    return ArrQueueItem(
      id: JsonRead.requiredInt(json, 'id'),
      title: JsonRead.string(json, 'title') ?? '',
      state: _state(json),
      size: size,
      sizeLeft: left > size ? size : left,
      timeLeft: parseArrTimeSpan(JsonRead.string(json, 'timeleft')),
      estimatedCompletion: JsonRead.date(json, 'estimatedCompletionTime'),
      protocol: parseArrProtocol(JsonRead.string(json, 'protocol')),
      downloadClient: JsonRead.string(json, 'downloadClient'),
      indexer: JsonRead.string(json, 'indexer'),
      downloadId: JsonRead.string(json, 'downloadId'),
      qualityName: quality == null ? null : JsonRead.string(quality, 'name'),
      added: JsonRead.date(json, 'added'),
      messages: [
        for (final m in JsonRead.list(json, 'statusMessages'))
          if (JsonRead.map(m) case final mm?) ArrStatusMessage.fromJson(mm),
      ],
      errorMessage: JsonRead.string(json, 'errorMessage'),
      seriesId: JsonRead.intOrNull(json, 'seriesId'),
      episodeId: JsonRead.intOrNull(json, 'episodeId'),
      seasonNumber:
          JsonRead.intOrNull(json, 'seasonNumber') ??
          (episode == null
              ? null
              : JsonRead.intOrNull(episode, 'seasonNumber')),
      episodeNumber: episode == null
          ? null
          : JsonRead.intOrNull(episode, 'episodeNumber'),
      movieId: JsonRead.intOrNull(json, 'movieId'),
      mediaTitle: series != null
          ? JsonRead.string(series, 'title')
          : (movie == null ? null : JsonRead.string(movie, 'title')),
      episodeTitle: episode == null ? null : JsonRead.string(episode, 'title'),
    );
  }

  final int id;

  /// The release name as grabbed.
  final String title;

  /// The download client's id for the item (a torrent info hash, for
  /// example), when the server reports one. Compared, never shown or logged.
  final String? downloadId;
  final ArrQueueState state;

  /// Bytes.
  final int size;
  final int sizeLeft;
  final Duration? timeLeft;
  final DateTime? estimatedCompletion;
  final ArrProtocol protocol;
  final String? downloadClient;
  final String? indexer;
  final String? qualityName;
  final DateTime? added;
  final List<ArrStatusMessage> messages;
  final String? errorMessage;
  final int? seriesId;
  final int? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? movieId;

  /// Series or movie title when the server embedded it (`includeSeries`).
  final String? mediaTitle;
  final String? episodeTitle;

  /// Fraction 0..1 downloaded (0 when the size is unknown).
  double get progress => size <= 0 ? 0 : (size - sizeLeft) / size;

  bool get hasWarnings => messages.isNotEmpty || errorMessage != null;

  @override
  bool operator ==(Object other) =>
      other is ArrQueueItem &&
      other.id == id &&
      other.title == title &&
      other.state == state &&
      other.size == size &&
      other.sizeLeft == sizeLeft &&
      other.timeLeft == timeLeft &&
      other.messages.length == messages.length &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(id, title, state, size, sizeLeft, timeLeft, errorMessage);

  @override
  String toString() => 'ArrQueueItem($id)';
}

int _num(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is num && v.isFinite && v >= 0) return v.toInt();
  return 0;
}

ArrQueueState _state(Map<String, Object?> json) {
  final status = JsonRead.string(json, 'status')?.toLowerCase();
  final tdStatus = JsonRead.string(
    json,
    'trackedDownloadStatus',
  )?.toLowerCase();
  final tdState = JsonRead.string(json, 'trackedDownloadState')?.toLowerCase();
  if (status == 'downloadclientunavailable') {
    return ArrQueueState.clientUnavailable;
  }
  switch (tdState) {
    case 'importfailed':
      return ArrQueueState.importFailed;
    case 'downloadfailed':
      return ArrQueueState.downloadFailed;
    case 'importpending':
      return ArrQueueState.importPending;
    case 'importing':
      return ArrQueueState.importing;
  }
  if (status == 'failed') return ArrQueueState.downloadFailed;
  if (status == 'paused') return ArrQueueState.paused;
  if (status == 'queued') return ArrQueueState.queued;
  if (status == 'delay') return ArrQueueState.delayed;
  if (status == 'completed') return ArrQueueState.completed;
  if (tdStatus == 'warning' || tdStatus == 'error' || status == 'warning') {
    return ArrQueueState.warning;
  }
  if (status == 'downloading') return ArrQueueState.downloading;
  return ArrQueueState.unknown;
}

/// Parses .NET `TimeSpan` text (`hh:mm:ss`, `d.hh:mm:ss`, optional fraction).
Duration? parseArrTimeSpan(String? text) {
  if (text == null) return null;
  final m = RegExp(r'^(?:(\d+)\.)?(\d{1,2}):(\d{2}):(\d{2})(?:\.\d+)?$')
      .firstMatch(text.trim());
  if (m == null) return null;
  return Duration(
    days: int.tryParse(m.group(1) ?? '') ?? 0,
    hours: int.parse(m.group(2)!),
    minutes: int.parse(m.group(3)!),
    seconds: int.parse(m.group(4)!),
  );
}

/// What to do about the release when removing a queue item.
enum ArrBlocklistChoice {
  /// Remove only.
  none,

  /// Blocklist the release and search for another one.
  blocklistAndSearch,

  /// Blocklist the release without searching again.
  blocklistOnly,
}
