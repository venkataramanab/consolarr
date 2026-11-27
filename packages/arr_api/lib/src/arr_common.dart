// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/json_read.dart';
import 'package:core/core.dart';

/// Artwork kinds the app uses (shared by Sonarr and Radarr).
enum ArrImageType { poster, banner, fanart, unknown }

ArrImageType _imageType(String? v) => switch (v) {
  'poster' => ArrImageType.poster,
  'banner' => ArrImageType.banner,
  'fanart' => ArrImageType.fanart,
  _ => ArrImageType.unknown,
};

/// One artwork reference. Only the server-relative [url] is kept; the
/// third-party `remoteUrl` is deliberately dropped so the app never contacts
/// other hosts.
class ArrImage {
  const ArrImage({required this.type, this.url});

  factory ArrImage.fromJson(Map<String, Object?> json) => ArrImage(
    type: _imageType(JsonRead.string(json, 'coverType')),
    url: JsonRead.string(json, 'url'),
  );

  final ArrImageType type;
  final String? url;

  Map<String, Object?> toJson() => {'coverType': type.name, 'url': url};

  @override
  bool operator ==(Object other) =>
      other is ArrImage && other.type == type && other.url == url;

  @override
  int get hashCode => Object.hash(type, url);
}

/// A quality profile (`/qualityprofile`): choose one when adding media.
class ArrQualityProfile {
  const ArrQualityProfile({required this.id, required this.name});

  factory ArrQualityProfile.fromJson(Map<String, Object?> json) =>
      ArrQualityProfile(
        id: JsonRead.requiredInt(json, 'id'),
        name: JsonRead.requiredString(json, 'name'),
      );

  final int id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ArrQualityProfile && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A root folder (`/rootfolder`): where media is stored.
class ArrRootFolder {
  const ArrRootFolder({required this.id, required this.path, this.freeSpace});

  factory ArrRootFolder.fromJson(Map<String, Object?> json) => ArrRootFolder(
    id: JsonRead.requiredInt(json, 'id'),
    path: JsonRead.requiredString(json, 'path'),
    freeSpace: JsonRead.intOrNull(json, 'freeSpace'),
  );

  final int id;

  /// Server-side path (plain text).
  final String path;

  /// Free bytes, when the server reports it.
  final int? freeSpace;

  @override
  bool operator ==(Object other) =>
      other is ArrRootFolder &&
      other.id == id &&
      other.path == path &&
      other.freeSpace == freeSpace;

  @override
  int get hashCode => Object.hash(id, path, freeSpace);
}

/// A tag (`/tag`).
class ArrTag {
  const ArrTag({required this.id, required this.label});

  factory ArrTag.fromJson(Map<String, Object?> json) => ArrTag(
    id: JsonRead.requiredInt(json, 'id'),
    label: JsonRead.requiredString(json, 'label'),
  );

  final int id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ArrTag && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// Parses an array body of [parse]d rows, skipping malformed rows (see
/// [parseRowsTolerant]). Throws [FormatException] for a non-array body.
ParsedRows<T> parseArrList<T>(
  Object? decoded,
  T Function(Map<String, Object?> json) parse,
) {
  if (decoded is! List) throw const FormatException('expected a JSON array');
  return parseRowsTolerant(
    decoded,
    (e) => parse(
      JsonRead.map(e) ?? (throw const FormatException('expected an object')),
    ),
  );
}
