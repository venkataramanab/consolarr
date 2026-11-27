// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The server list for UI that is visible on the first frame. Stays in the
/// loading state until the first frame is done, so reading it never starts
/// database work before then.
final uiServersProvider = Provider<AsyncValue<List<ServerEntry>>>((ref) {
  if (!ref.watch(firstFrameDoneProvider)) return const AsyncValue.loading();
  return ref.watch(serversProvider);
});

/// The primary destinations of the shell, in bar order.
enum ShellDestination { home, sonarr, torrents, servers }

/// Which destinations the bar shows (NAV-01): Home and Servers always; a
/// service area only when a server of that kind is configured.
List<ShellDestination> visibleDestinations(List<ServerEntry> servers) {
  bool has(ServiceKind kind) => servers.any((s) => s.profile.kind == kind);
  return [
    ShellDestination.home,
    if (has(ServiceKind.sonarr)) ShellDestination.sonarr,
    if (has(ServiceKind.qbittorrent)) ShellDestination.torrents,
    ShellDestination.servers,
  ];
}

final visibleDestinationsProvider = Provider<List<ShellDestination>>((ref) {
  final servers = ref.watch(uiServersProvider).value ?? const [];
  return visibleDestinations(servers);
});
