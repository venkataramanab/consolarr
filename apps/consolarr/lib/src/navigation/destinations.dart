// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/home/home_routes.dart';
import 'package:consolarr/features/radarr/radarr_routes.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/servers_routes.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/features/torrents/torrents_routes.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:core/core.dart';

/// The primary destinations in bar order; also the order of the shell
/// branches. Each feature contributes its descriptor(s) from
/// `features/<feature>/<feature>_routes.dart`. A new feature adds exactly one
/// line, in its own slot, here.
final List<AppDestination> appDestinations = [
  homeDestination,
  sonarrDestination,
  radarrDestination,
  torrentsDestination,
  // settingsDestination, (W4 Design + Settings)
  serversDestination,
];

/// The route a server of [kind] is used in (for example after onboarding), or
/// `null` when no destination serves it.
String? routeForKind(ServiceKind kind, {List<AppDestination>? destinations}) {
  for (final d in destinations ?? appDestinations) {
    if (d.servesKind(kind)) return d.route;
  }
  return null;
}

/// Indices (into [destinations]) of the destinations the bar shows: the ones
/// without a service requirement, the ones whose service has a configured
/// server, and always the branch that is open ([currentIndex]).
List<int> visibleDestinationIndices(
  List<ServerEntry> servers, {
  required int currentIndex,
  List<AppDestination>? destinations,
}) {
  final all = destinations ?? appDestinations;
  final kinds = {for (final s in servers) s.profile.kind};
  return [
    for (var i = 0; i < all.length; i++)
      if (i == currentIndex ||
          all[i].kinds == null ||
          all[i].kinds!.any(kinds.contains))
        i,
  ];
}
