// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/json_read.dart';
import 'package:arr_api/src/shared/arr_queue.dart';

/// One release found by an interactive search (`GET /release`).
///
/// Everything here is server (indexer) text: plain text only, never logged or
/// reported, and never turned into a link.
class ArrRelease {
  const ArrRelease({
    required this.guid,
    required this.title,
    this.indexerId = 0,
    this.indexer,
    this.size = 0,
    this.ageMinutes = 0,
    this.seeders,
    this.leechers,
    this.protocol = ArrProtocol.unknown,
    this.qualityName,
    this.resolution,
    this.source,
    this.approved = true,
    this.rejections = const [],
    this.downloadAllowed = true,
    this.temporarilyRejected = false,
    this.customFormats = const [],
    this.customFormatScore = 0,
    this.languages = const [],
    this.fullSeason = false,
    this.seasonNumber,
    this.releaseWeight = 0,
  });

  factory ArrRelease.fromJson(Map<String, Object?> json) {
    final qualityOuter = JsonRead.map(json['quality']);
    final quality = JsonRead.map(qualityOuter?['quality']);
    final rejections = [
      for (final r in JsonRead.list(json, 'rejections'))
        if (r is String && r.isNotEmpty) r,
    ];
    final approved = json['approved'] is bool
        ? json['approved']! as bool
        : rejections.isEmpty;
    final age = JsonRead.intOrNull(json, 'ageMinutes');
    final ageDays = JsonRead.intOrNull(json, 'age');
    return ArrRelease(
      guid: JsonRead.requiredString(json, 'guid'),
      title: JsonRead.string(json, 'title') ?? '',
      indexerId: JsonRead.integer(json, 'indexerId'),
      indexer: JsonRead.string(json, 'indexer'),
      size: _nonNeg(JsonRead.intOrNull(json, 'size')),
      ageMinutes: age ?? (ageDays == null ? 0 : ageDays * 24 * 60),
      seeders: JsonRead.intOrNull(json, 'seeders'),
      leechers: JsonRead.intOrNull(json, 'leechers'),
      protocol: parseArrProtocol(JsonRead.string(json, 'protocol')),
      qualityName: quality == null ? null : JsonRead.string(quality, 'name'),
      resolution: quality == null
          ? null
          : JsonRead.intOrNull(quality, 'resolution'),
      source: quality == null ? null : JsonRead.string(quality, 'source'),
      approved: approved,
      rejections: rejections,
      downloadAllowed: json['downloadAllowed'] is bool
          ? json['downloadAllowed']! as bool
          : true,
      temporarilyRejected: JsonRead.boolean(json, 'temporarilyRejected'),
      customFormats: _names(JsonRead.list(json, 'customFormats')),
      customFormatScore: JsonRead.integer(json, 'customFormatScore'),
      languages: _names(JsonRead.list(json, 'languages')),
      fullSeason: JsonRead.boolean(json, 'fullSeason'),
      seasonNumber: JsonRead.intOrNull(json, 'seasonNumber'),
      releaseWeight: JsonRead.integer(json, 'releaseWeight'),
    );
  }

  /// Identifies the release for the grab request.
  final String guid;
  final String title;
  final int indexerId;
  final String? indexer;

  /// Bytes.
  final int size;
  final int ageMinutes;
  final int? seeders;
  final int? leechers;
  final ArrProtocol protocol;
  final String? qualityName;

  /// Vertical resolution (720, 1080, ...), when known.
  final int? resolution;

  /// Quality source (`webdl`, `bluray`, ...), when known.
  final String? source;
  final bool approved;

  /// Why the server rejected it; empty when accepted.
  final List<String> rejections;
  final bool downloadAllowed;
  final bool temporarilyRejected;
  final List<String> customFormats;
  final int customFormatScore;
  final List<String> languages;
  final bool fullSeason;
  final int? seasonNumber;

  /// Server order: lower is better ("best match").
  final int releaseWeight;

  bool get isRejected => !approved || rejections.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ArrRelease && other.guid == guid && other.indexerId == indexerId;

  @override
  int get hashCode => Object.hash(guid, indexerId);

  @override
  String toString() => 'ArrRelease($indexerId)';
}

int _nonNeg(int? v) => v == null || v < 0 ? 0 : v;

List<String> _names(List<Object?> items) => [
  for (final e in items)
    if (JsonRead.map(e) case final m?)
      if (JsonRead.string(m, 'name') case final n? when n.isNotEmpty) n,
];
