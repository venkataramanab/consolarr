// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';

/// Route paths used by the servers screens. The app router (`AppRoutes`) maps
/// these to screens; screens navigate with these constants only.
abstract final class ServersRoutes {
  static const list = '/servers';
  static const newServer = '/servers/new';
  static const editPattern = '/servers/:id';
  static const onboarding = '/onboarding';

  static String edit(String id) => '/servers/${Uri.encodeComponent(id)}';

  /// Where onboarding sends the user after the first server was added.
  static String afterOnboarding(ServiceKind kind) => switch (kind) {
    ServiceKind.sonarr || ServiceKind.radarr => '/sonarr',
    ServiceKind.qbittorrent ||
    ServiceKind.transmission ||
    ServiceKind.deluge => '/torrents',
  };
}
