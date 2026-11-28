// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';

/// Sonarr and Radarr authenticate their API with the API key only. A username
/// and password can only matter to a reverse proxy in front of them, so these
/// kinds always need the key and treat the login as an optional extra.
extension ServiceKindAuth on ServiceKind {
  bool get isArr => this == ServiceKind.sonarr || this == ServiceKind.radarr;
}

/// A stored server plus facts the list needs. Holds no secret values.
class ServerEntry {
  const ServerEntry({
    required this.profile,
    required this.sortOrder,
    this.isStartup = false,
    this.needsCredentials = false,
    this.hasApiKey = true,
    this.proxyLogin = false,
  });

  final ServerProfile profile;
  final int sortOrder;

  /// The server opened on launch (SRV-01).
  final bool isStartup;

  /// A required secret is missing (Keystore loss, SRV-09): the UI prompts for
  /// re-entry instead of failing.
  final bool needsCredentials;

  /// An API key is stored. [needsCredentials] is also true when some other
  /// secret is lost (a custom-header value), which must not ask for the key
  /// again; only this says whether the key itself is there.
  final bool hasApiKey;

  /// A reverse-proxy login (HTTP Basic, sent in addition to the API key) is
  /// stored for this Sonarr or Radarr server. Derived from the secret store,
  /// so no profile column is needed; profiles saved in the old arr `basic`
  /// mode count when their username and password are still stored.
  final bool proxyLogin;

  /// A Sonarr or Radarr profile saved before the API key became mandatory
  /// (auth mode `basic` or `none`). The editor opens it with the key required.
  bool get isLegacyArrAuth =>
      profile.kind.isArr && profile.authMode != AuthMode.apiKey;
}

/// What a live connection is built from: the active server of a kind and a
/// revision that `ServerRepository.save` bumps on every write (profile or
/// credential edits). A change in either means "rebuild the connection".
class ConnectionKey {
  const ConnectionKey(this.serverId, this.revision);

  /// `null` when no server of the kind exists.
  final String? serverId;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ConnectionKey &&
      other.serverId == serverId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(serverId, revision);

  @override
  String toString() => 'ConnectionKey($serverId, $revision)';
}

/// One custom request header (SRV-04). The value is a secret.
class HeaderEntry {
  const HeaderEntry({required this.name, required this.value});
  final String name;
  final String value;
}

/// Secret values for one server. Any field may be absent.
class ServerCredentials {
  const ServerCredentials({
    this.apiKey,
    this.username,
    this.password,
    this.headers = const [],
  });

  static const empty = ServerCredentials();

  final String? apiKey;
  final String? username;
  final String? password;
  final List<HeaderEntry> headers;
}

/// Everything the editor collects (SRV-02, SRV-04, SRV-07). Not validated
/// until it goes through `ServerProfile.parse` in the repository.
class ServerDraft {
  const ServerDraft({
    required this.name,
    required this.kind,
    required this.address,
    this.id,
    this.pathPrefix = '',
    this.authMode = AuthMode.apiKey,
    this.allowCleartext = false,
    this.credentials = ServerCredentials.empty,
  });

  /// `null` for a new server; the repository assigns the id.
  final String? id;
  final String name;
  final ServiceKind kind;
  final String address;
  final String pathPrefix;
  final AuthMode authMode;
  final bool allowCleartext;
  final ServerCredentials credentials;
}

/// Result of a connection test (SRV-05).
sealed class ConnectionTestOutcome {
  const ConnectionTestOutcome();
}

final class ConnectionTestSuccess extends ConnectionTestOutcome {
  const ConnectionTestSuccess({required this.version, this.majorVersion});

  /// Display version string of the server (plain text from the server).
  final String version;
  final int? majorVersion;
}

final class ConnectionTestFailure extends ConnectionTestOutcome {
  const ConnectionTestFailure(this.error);

  /// May be a `CertificateDecisionRequired` / `TlsPinMismatch` /
  /// `CertificateExpired` from the security package, which the UI answers with
  /// the trust sheet.
  final AppError error;
}

/// Health of one server for the list (SRV-10).
enum ServerHealth { checking, healthy, degraded, unauthorized, unreachable }
