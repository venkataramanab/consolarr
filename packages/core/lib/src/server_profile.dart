// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/src/app_error.dart';
import 'package:core/src/result.dart';

/// The kind of remote service a [ServerProfile] points at.
enum ServiceKind { sonarr, radarr, qbittorrent, transmission, deluge }

/// A configured server.
///
/// Holds no secrets: credentials and API keys live in the secret store keyed
/// by [id], and certificate pins in the pin store keyed by host. The [address]
/// never contains user info (see [ServerProfile.parse]).
class ServerProfile {
  const ServerProfile._({
    required this.id,
    required this.name,
    required this.kind,
    required this.address,
    required this.allowCleartext,
  });

  /// Validates and builds a profile.
  ///
  /// Fails with [ErrorCategory.parseError] when [address] is not an absolute
  /// http(s) URL with a host, or contains credentials (user info).
  static Result<ServerProfile> parse({
    required String id,
    required String name,
    required ServiceKind kind,
    required String address,
    bool allowCleartext = false,
  }) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return const Result.err(
        AppError(ErrorCategory.parseError, debugDetail: 'invalid address'),
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
    return Result.ok(
      ServerProfile._(
        id: id,
        name: name,
        kind: kind,
        address: uri.removeFragment(),
        allowCleartext: allowCleartext,
      ),
    );
  }

  final String id;
  final String name;
  final ServiceKind kind;

  /// Base URL without credentials.
  final Uri address;

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
      );

  @override
  bool operator ==(Object other) =>
      other is ServerProfile &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.address == address &&
      other.allowCleartext == allowCleartext;

  @override
  int get hashCode => Object.hash(id, name, kind, address, allowCleartext);

  /// Deliberately omits [address] so logs never carry hosts or paths.
  @override
  String toString() => 'ServerProfile($id, ${kind.name})';
}
