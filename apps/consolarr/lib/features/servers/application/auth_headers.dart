// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';

/// Builds the credential headers for one service kind (the profile's custom
/// headers are added by [buildAuthHeaders] for every kind).
typedef AuthHeaderBuilder = Map<String, String> Function(
  ServerProfile profile,
  ServerCredentials credentials,
);

/// `X-Api-Key`, or `Authorization: Basic` for a reverse proxy in front of an
/// *arr service. Never a query parameter.
Map<String, String> arrAuthHeaders(
  ServerProfile profile,
  ServerCredentials credentials,
) {
  switch (profile.authMode) {
    case AuthMode.none:
      return const {};
    case AuthMode.apiKey:
      final key = credentials.apiKey;
      return key != null && key.isNotEmpty && _safe(key)
          ? {'X-Api-Key': key}
          : const {};
    case AuthMode.basic:
      final user = credentials.username;
      final pass = credentials.password;
      return user != null && pass != null
          ? {
              'Authorization':
                  'Basic ${base64.encode(utf8.encode('$user:$pass'))}',
            }
          : const {};
  }
}

/// Torrent clients log in themselves (cookie, session id, RPC login) from the
/// username and password, so they get no credential header.
Map<String, String> noCredentialHeaders(
  ServerProfile profile,
  ServerCredentials credentials,
) => const {};

/// Credential headers per kind. A new service registers here; a kind that is
/// not registered gets no credential header at all (the safe default), only
/// its declared custom headers.
const Map<ServiceKind, AuthHeaderBuilder> authHeaderBuilders = {
  ServiceKind.sonarr: arrAuthHeaders,
  ServiceKind.radarr: arrAuthHeaders,
  ServiceKind.qbittorrent: noCredentialHeaders,
  ServiceKind.transmission: noCredentialHeaders,
  ServiceKind.deluge: noCredentialHeaders,
};

/// The request headers that authenticate against [profile] (SRV-04).
///
/// * Credentials: per kind, see [authHeaderBuilders].
/// * Custom headers: only names the profile declares, values from the secret
///   store; values with line breaks are dropped (header injection).
Map<String, String> buildAuthHeaders(
  ServerProfile profile,
  ServerCredentials credentials,
) {
  final headers = <String, String>{
    ...?authHeaderBuilders[profile.kind]?.call(profile, credentials),
  };
  for (final name in profile.headerNames) {
    for (final h in credentials.headers) {
      if (h.name.toLowerCase() == name.toLowerCase() && _safe(h.value)) {
        headers[name] = h.value;
      }
    }
  }
  return headers;
}

bool _safe(String value) => !value.contains(RegExp(r'[\r\n\x00]'));
