// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';

/// The request headers that authenticate against [profile] (SRV-04).
///
/// * API key: `X-Api-Key` (never a query parameter).
/// * Basic: an `Authorization: Basic` header for the *arr services. The
///   qBittorrent client performs its own cookie login from the username and
///   password, so it gets no header here.
/// * Custom headers: only names the profile declares, values from the secret
///   store; values with line breaks are dropped (header injection).
Map<String, String> buildAuthHeaders(
  ServerProfile profile,
  ServerCredentials credentials,
) {
  final headers = <String, String>{};
  final isArr =
      profile.kind == ServiceKind.sonarr || profile.kind == ServiceKind.radarr;
  switch (profile.authMode) {
    case AuthMode.none:
      break;
    case AuthMode.apiKey:
      final key = credentials.apiKey;
      if (isArr && key != null && key.isNotEmpty && _safe(key)) {
        headers['X-Api-Key'] = key;
      }
    case AuthMode.basic:
      final user = credentials.username;
      final pass = credentials.password;
      if (isArr && user != null && pass != null) {
        headers['Authorization'] =
            'Basic ${base64.encode(utf8.encode('$user:$pass'))}';
      }
  }
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
