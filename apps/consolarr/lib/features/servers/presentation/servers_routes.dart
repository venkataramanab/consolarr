// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/presentation/servers_list_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/navigation/destinations.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

/// Route paths used by the servers screens. The app router (`AppRoutes`) maps
/// these to screens; screens navigate with these constants only.
abstract final class ServersRoutes {
  static const list = '/servers';
  static const newServer = '/servers/new';
  static const editPattern = '/servers/:id';
  static const onboarding = '/onboarding';

  static String edit(String id) => '/servers/${Uri.encodeComponent(id)}';

  /// Where onboarding sends the user after the first server was added: the
  /// destination that serves [kind] (from the destination descriptors).
  static String afterOnboarding(ServiceKind kind) => routeForKind(kind) ?? list;
}

/// Servers tab: always offered.
final serversDestination = AppDestination(
  id: 'servers',
  route: ServersRoutes.list,
  icon: Icons.dns_outlined,
  selectedIcon: Icons.dns,
  label: (l10n) => l10n.navServers,
  builder: (context, state) => const ServersListScreen(),
);
