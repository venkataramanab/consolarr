// SPDX-License-Identifier: GPL-3.0-or-later

/// Most path segments a logged route keeps.
const _maxSegments = 8;

/// What joins the segments of a logged route. The diagnostics scrubber treats
/// `/` as a file path and `.` as a host name, so a logged route contains
/// neither (and no `:`, which reads as an IPv6 address).
const routeSeparator = '·';

/// The closed vocabulary of route words a log line may carry: every segment
/// of every endpoint the clients call (Sonarr and Radarr v3, qBittorrent
/// `api/v2`, Transmission `transmission/rpc`, Deluge `json`) plus the artwork
/// routes. A segment that is not here never reaches a log line, so a title, a
/// slug, a hash or a user-chosen path can only appear as `{seg}`.
///
/// Case matters: `Movie` is not `movie`. A test reads the clients' own route
/// literals and fails when one has a word missing here.
const routeVocabulary = <String>{
  // Shared.
  'api', 'v2', 'v3', 'json', 'system', 'status', 'lookup', 'command',
  // Sonarr and Radarr.
  'calendar', 'episode', 'monitor', 'languageprofile', 'movie',
  'qualityprofile', 'queue', 'release', 'rootfolder', 'series', 'tag',
  'wanted', 'cutoff', 'missing', 'history',
  // Artwork.
  'MediaCover', 'MediaCoverProxy',
  // qBittorrent.
  'app', 'version', 'auth', 'login', 'torrents', 'add', 'delete', 'info',
  'pause', 'properties', 'resume', 'start', 'stop', 'transfer',
  'downloadLimit', 'setDownloadLimit', 'setUploadLimit', 'speedLimitsMode',
  'toggleSpeedLimitsMode', 'uploadLimit',
  // Transmission.
  'transmission', 'rpc',
};

/// The fixed artwork file names Sonarr and Radarr serve (`poster.jpg`,
/// `fanart-1280.jpg`). The dot is written `_`, so the name survives the
/// scrubber's host rule (`poster-500_jpg`). Any other file name is `{seg}`.
final _artworkFile = RegExp(
  r'^(poster|banner|fanart|cover|clearlogo|logo|headshot|screenshot|'
  r'disc|keyart)(-\d{1,4})?\.(jpg|jpeg|png|webp)$',
);

final _digits = RegExp(r'^\d{1,18}$');

/// The route shape of [path] for logs, for example
/// `api·v3·movie·{id}` for `/radarr/api/v3/movie/123?x=y` with prefix
/// `/radarr`.
///
/// * No host, port, userinfo, query, fragment or [pathPrefix].
/// * A segment from [routeVocabulary] is kept as it is.
/// * A run of digits is `{id}`; an artwork file name is `poster-500_jpg`.
/// * Anything else is `{seg}`, so a title, slug, hash or secret in a path
///   cannot reach a log line by construction.
/// * Segments are joined with [routeSeparator]: the result has no `/`, `.`
///   or `:`.
String routeShape(String path, {String pathPrefix = ''}) {
  var p = path;
  final scheme = p.indexOf('://');
  if (scheme >= 0) {
    // Cut `scheme://authority`; what remains starts at the first slash.
    final slash = p.indexOf('/', scheme + 3);
    p = slash < 0 ? '/' : p.substring(slash);
  }
  final cut = p.indexOf(RegExp('[?#]'));
  if (cut >= 0) p = p.substring(0, cut);

  final segments = p.split('/').where((s) => s.isNotEmpty).toList();
  final prefix = pathPrefix.split('/').where((s) => s.isNotEmpty).toList();
  if (prefix.isNotEmpty &&
      segments.length >= prefix.length &&
      [for (var i = 0; i < prefix.length; i++) segments[i] == prefix[i]]
          .every((m) => m)) {
    segments.removeRange(0, prefix.length);
  }
  if (segments.isEmpty) return '{root}';

  return [
    for (final s in segments.take(_maxSegments)) _shapeSegment(s),
    if (segments.length > _maxSegments) '{more}',
  ].join(routeSeparator);
}

String _shapeSegment(String s) {
  if (routeVocabulary.contains(s)) return s;
  if (_digits.hasMatch(s)) return '{id}';
  if (_artworkFile.hasMatch(s)) return s.replaceAll('.', '_');
  return '{seg}';
}
