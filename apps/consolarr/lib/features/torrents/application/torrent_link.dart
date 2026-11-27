// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

/// Why a pasted link was refused.
enum LinkProblem { empty, scheme, hash, userinfo, url }

/// The result of checking a magnet link or torrent URL (TOR-04).
///
/// The raw link may embed tracker passkeys: only [displayName] / [host] are
/// meant for the screen, and nothing here is ever logged.
sealed class ParsedLink {
  const ParsedLink();
}

final class MagnetLink extends ParsedLink {
  const MagnetLink({required this.displayName});

  /// The `dn` parameter (plain text), or a short form of the info hash.
  final String displayName;
}

final class UrlLink extends ParsedLink {
  const UrlLink({required this.host});
  final String host;
}

final class InvalidLink extends ParsedLink {
  const InvalidLink(this.problem);
  final LinkProblem problem;
}

final _hex40 = RegExp(r'^[0-9a-fA-F]{40}$');
final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
final _base32 = RegExp(r'^[A-Za-z2-7]{32}$');

/// Checks [input] (trimmed): `magnet:` with a valid info hash, or `http(s)`
/// without userinfo. Anything else is invalid.
ParsedLink parseTorrentLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return const InvalidLink(LinkProblem.empty);
  if (text.toLowerCase().startsWith('magnet:')) return _magnet(text);
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return const InvalidLink(LinkProblem.url);
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return const InvalidLink(LinkProblem.scheme);
  }
  if (uri.userInfo.isNotEmpty) return const InvalidLink(LinkProblem.userinfo);
  if (uri.host.isEmpty) return const InvalidLink(LinkProblem.url);
  return UrlLink(host: uri.host);
}

ParsedLink _magnet(String text) {
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return const InvalidLink(LinkProblem.hash);
  }
  final params = <String, List<String>>{};
  for (final part in uri.query.split('&')) {
    if (part.isEmpty) continue;
    final i = part.indexOf('=');
    final key = i < 0 ? part : part.substring(0, i);
    final value = i < 0 ? '' : part.substring(i + 1);
    try {
      (params[key.toLowerCase()] ??= []).add(Uri.decodeQueryComponent(value));
    } on ArgumentError {
      (params[key.toLowerCase()] ??= []).add('');
    }
  }
  String? hash;
  for (final xt in params['xt'] ?? const <String>[]) {
    final lower = xt.toLowerCase();
    if (lower.startsWith('urn:btih:')) {
      final h = xt.substring(9);
      if (_hex40.hasMatch(h) || _base32.hasMatch(h)) hash = h;
    } else if (lower.startsWith('urn:btmh:')) {
      final h = xt.substring(9);
      // Multihash of SHA-256: `1220` + 64 hex.
      if (h.length == 68 &&
          h.toLowerCase().startsWith('1220') &&
          _hex64.hasMatch(h.substring(4))) {
        hash = h;
      }
    }
  }
  if (hash == null) return const InvalidLink(LinkProblem.hash);
  final dn = (params['dn'] ?? const <String>[]).firstOrNull?.trim() ?? '';
  return MagnetLink(displayName: dn.isEmpty ? hash.substring(0, 12) : dn);
}

/// The largest `.torrent` file accepted (a torrent is a small index file).
const maxTorrentFileBytes = 5 * 1024 * 1024;

/// Why a file was refused.
enum FileProblem { tooLarge, notTorrent }

/// Checks that [bytes] look like a torrent: a bencoded dictionary that
/// contains an `info` key. `null` means acceptable.
FileProblem? checkTorrentBytes(Uint8List bytes) {
  if (bytes.length > maxTorrentFileBytes) return FileProblem.tooLarge;
  // Dictionary: starts with `d`, ends with `e`, has an `info` entry.
  if (bytes.length < 8 || bytes.first != 0x64 || bytes.last != 0x65) {
    return FileProblem.notTorrent;
  }
  const needle = [0x34, 0x3a, 0x69, 0x6e, 0x66, 0x6f]; // 4:info
  final end = bytes.length - needle.length;
  for (var i = 1; i <= end; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return null;
  }
  return FileProblem.notTorrent;
}
