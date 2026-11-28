// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Service types the editor offers. Add a kind here (and its client) to
/// extend the picker; nothing else in the form changes.
const supportedServiceKinds = [
  ServiceKind.sonarr,
  ServiceKind.radarr,
  ServiceKind.qbittorrent,
  ServiceKind.transmission,
  ServiceKind.deluge,
];

/// Authentication modes a service offers, strongest first.
List<AuthMode> authModesFor(ServiceKind kind) => switch (kind) {
  // The arr API takes the API key only; a username and password are an
  // optional reverse-proxy login, not a mode (see `ServiceKindAuth`).
  ServiceKind.sonarr || ServiceKind.radarr => const [AuthMode.apiKey],
  _ => const [AuthMode.basic, AuthMode.none],
};

/// The auth mode preselected for a new server of [kind].
AuthMode defaultAuthModeFor(ServiceKind kind) => authModesFor(kind).first;

IconData serviceKindIcon(ServiceKind kind) => switch (kind) {
  ServiceKind.sonarr => Icons.tv_outlined,
  ServiceKind.radarr => Icons.movie_outlined,
  _ => Icons.downloading_outlined,
};

String serviceKindLabel(AppLocalizations l10n, ServiceKind kind) =>
    switch (kind) {
      ServiceKind.sonarr => l10n.serverKindSonarr,
      ServiceKind.radarr => l10n.serverKindRadarr,
      ServiceKind.qbittorrent => l10n.serverKindQbittorrent,
      ServiceKind.transmission => l10n.serverKindTransmission,
      ServiceKind.deluge => l10n.serverKindDeluge,
    };

String serviceKindDescription(AppLocalizations l10n, ServiceKind kind) =>
    switch (kind) {
      ServiceKind.sonarr => l10n.serverKindSonarrDescription,
      ServiceKind.radarr => l10n.radarrKindDescription,
      ServiceKind.qbittorrent => l10n.serverKindQbittorrentDescription,
      ServiceKind.transmission => l10n.torKindTransmissionDescription,
      ServiceKind.deluge => l10n.torKindDelugeDescription,
    };

String authModeLabel(AppLocalizations l10n, AuthMode mode) => switch (mode) {
  AuthMode.none => l10n.serverAuthNone,
  AuthMode.apiKey => l10n.serverAuthApiKey,
  AuthMode.basic => l10n.serverAuthBasic,
};
