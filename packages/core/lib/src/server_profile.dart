// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/src/app_error.dart';
import 'package:core/src/result.dart';

/// The kind of remote service a [ServerProfile] points at.
enum ServiceKind { sonarr, radarr, qbittorrent, transmission, deluge }

/// How the app authenticates against a server (SRV-04).
///
/// The secrets themselves (API key, username, password, header values) live in
/// the secret store, never in the profile.
enum AuthMode {
  /// No credentials (e.g. a server that bypasses auth on the LAN).
  none,

  /// A single API key (sent in a header, never in the URL).
  apiKey,

  /// Username and password (HTTP basic or a login form, per service).
  basic,
}

/// A configured server.
///
/// Holds no secrets: credentials and API keys live in the secret store keyed
/// by [id], and certificate pins in the pin store keyed by profile id, host and
/// port. The [address] never contains user info or a query string (see
/// [ServerProfile.parse]).
class ServerProfile {
  const ServerProfile._({
    required this.id,
    required this.name,
    required this.kind,
    required this.address,
    required this.allowCleartext,
    required this.pathPrefix,
    required this.authMode,
    required this.headerNames,
    required this.alternateAddress,
  });

  /// Validates and builds a profile.
  ///
  /// Fails with [ErrorCategory.parseError] when [address] is not an absolute
  /// http(s) URL with a host, or contains credentials (user info) or a query
  /// string (API keys and tokens must never be stored in the address).
  static Result<ServerProfile> parse({
    required String id,
    required String name,
    required ServiceKind kind,
    required String address,
    bool allowCleartext = false,
    String pathPrefix = '',
    AuthMode authMode = AuthMode.apiKey,
    List<String> headerNames = const [],
    String? alternateAddress,
  }) {
    final primary = _parseAddress(address);
    if (primary.isErr) return Result.err(primary.errorOrNull!);
    final uri = primary.valueOrNull!;

    // A path typed into the address is folded into the prefix, so the
    // invariant `address.path.isEmpty` always holds.
    final prefix = _normalizePrefix(
      '${uri.path.isEmpty || uri.path == '/' ? '' : uri.path}/$pathPrefix',
    );
    if (prefix == null) {
      return const Result.err(
        AppError(ErrorCategory.parseError, debugDetail: 'invalid path prefix'),
      );
    }

    if (headerNames.length > maxHeaders ||
        headerNames.any((h) => !_headerToken.hasMatch(h)) ||
        headerNames.map((h) => h.toLowerCase()).toSet().length !=
            headerNames.length) {
      return const Result.err(
        AppError(ErrorCategory.parseError, debugDetail: 'invalid headers'),
      );
    }

    Uri? alternate;
    if (alternateAddress != null && alternateAddress.trim().isNotEmpty) {
      final alt = _parseAddress(alternateAddress);
      if (alt.isErr) return Result.err(alt.errorOrNull!);
      alternate = alt.valueOrNull!.replace(path: '');
    }

    return Result.ok(
      ServerProfile._(
        id: id,
        name: name,
        kind: kind,
        address: uri.replace(path: ''),
        allowCleartext: allowCleartext,
        pathPrefix: prefix,
        authMode: authMode,
        headerNames: List.unmodifiable(headerNames),
        alternateAddress: alternate,
      ),
    );
  }

  /// Most custom request headers a profile may declare.
  static const maxHeaders = 20;

  static final _headerToken = RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]{1,64}$");
  static final _badPathChars = RegExp(r'[\s?#\\\x00-\x1f\x7f]');

  static Result<Uri> _parseAddress(String address) {
    final trimmed = address.trim();
    // A backslash is a path separator to some parsers and an authority
    // terminator to others (`https://evil\@nas`): never accept it.
    final uri = trimmed.contains(r'\') ? null : Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return const Result.err(
        AppError(ErrorCategory.parseError, debugDetail: 'invalid address'),
      );
    }
    if (uri.host.codeUnits.any((c) => c > 0x7e || c < 0x21 || c == 0x25)) {
      return const Result.err(
        AppError(ErrorCategory.parseError, debugDetail: 'host must be ascii'),
      );
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return const Result.err(
        AppError(ErrorCategory.parseError, debugDetail: 'invalid port'),
      );
    }
    if (uri.userInfo.isNotEmpty) {
      return const Result.err(
        AppError(
          ErrorCategory.parseError,
          debugDetail: 'address must not contain credentials',
        ),
      );
    }
    // `uri.hasQuery` is also true for a bare trailing `?`.
    if (uri.hasQuery) {
      return const Result.err(
        AppError(
          ErrorCategory.parseError,
          debugDetail: 'address must not contain a query string',
        ),
      );
    }
    return Result.ok(uri.removeFragment());
  }

  /// `''` or `/a/b`; null when unsafe (traversal, query, whitespace, ...).
  static String? _normalizePrefix(String raw) {
    if (_badPathChars.hasMatch(raw)) return null;
    final segments = raw.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '.' || s == '..')) return null;
    return segments.isEmpty ? '' : '/${segments.join('/')}';
  }

  final String id;
  final String name;
  final ServiceKind kind;

  /// Origin (scheme, host, port) without credentials or path.
  final Uri address;

  /// Reverse-proxy path prefix: `''` or `/segment[/segment]`, no trailing slash.
  final String pathPrefix;

  /// How to authenticate; the secrets live in the secret store.
  final AuthMode authMode;

  /// Names of custom request headers (values are secrets, stored apart).
  final List<String> headerNames;

  /// A second address for the same server (SRV-03, for example LAN vs public).
  /// Reserved: the first release uses [address] only.
  final Uri? alternateAddress;

  /// [address] plus [pathPrefix]: the root every API path is appended to.
  Uri get baseUri => address.replace(path: pathPrefix);

  /// Explicit per-server opt-in to plain http. Defaults to `false`.
  final bool allowCleartext;

  bool get isSecure => address.scheme == 'https';

  ServerProfile copyWith({String? name, bool? allowCleartext}) =>
      ServerProfile._(
        id: id,
        name: name ?? this.name,
        kind: kind,
        address: address,
        allowCleartext: allowCleartext ?? this.allowCleartext,
        pathPrefix: pathPrefix,
        authMode: authMode,
        headerNames: headerNames,
        alternateAddress: alternateAddress,
      );

  @override
  bool operator ==(Object other) =>
      other is ServerProfile &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.address == address &&
      other.allowCleartext == allowCleartext &&
      other.pathPrefix == pathPrefix &&
      other.authMode == authMode &&
      other.alternateAddress == alternateAddress &&
      _sameList(other.headerNames, headerNames);

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    address,
    allowCleartext,
    pathPrefix,
    authMode,
    alternateAddress,
    Object.hashAll(headerNames),
  );

  /// Deliberately omits [address] so logs never carry hosts or paths.
  @override
  String toString() => 'ServerProfile($id, ${kind.name})';
}
