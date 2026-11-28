// SPDX-License-Identifier: GPL-3.0-or-later

/// Most path segments a logged route keeps.
const _maxSegments = 8;

/// A plain route word (`api`, `v3`, `MediaCover`): letters first, then
/// letters or digits. Ids, hashes, titles and slugs never look like this
/// (digits first, hyphens, percent escapes, dots).
final _routeWord = RegExp(r'^[A-Za-z][A-Za-z0-9]{0,23}$');

/// A long run of hex digits is a hash or id even though it is made of letters.
final _hex = RegExp(r'^[0-9a-fA-F]{8,}$');

/// The fixed artwork file names Sonarr and Radarr serve (`poster.jpg`,
/// `fanart-1280.jpg`). Any other file name is replaced.
final _artworkFile = RegExp(
  r'^(poster|banner|fanart|cover|clearlogo|logo|headshot|screenshot|'
  r'disc|keyart)(-\d{1,4})?\.(jpg|jpeg|png|webp)$',
);

/// The route shape of [path] for logs: no host, port, userinfo, query,
/// fragment or [pathPrefix], and every segment that could carry an id, a hash
/// or a title replaced by `{id}` (or `{file}`).
///
/// `/radarr/api/v3/movie/123?x=y` with prefix `/radarr` becomes
/// `/api/v3/movie/{id}`. Only plain route words survive, so a title or a
/// secret in a path cannot reach a log line by construction.
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

  final shaped = [
    for (final s in segments.take(_maxSegments)) _shapeSegment(s),
    if (segments.length > _maxSegments) '...',
  ];
  return '/${shaped.join('/')}';
}

String _shapeSegment(String s) {
  if (_artworkFile.hasMatch(s)) return s;
  if (s.contains('.')) return '{file}';
  if (_routeWord.hasMatch(s) && !_hex.hasMatch(s)) return s;
  return '{id}';
}
