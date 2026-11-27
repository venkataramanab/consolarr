// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/add/add_series_screen.dart';
import 'package:consolarr/features/sonarr/presentation/detail/series_detail_screen.dart';
import 'package:consolarr/features/sonarr/presentation/home/sonarr_home_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the Sonarr home (library and its tabs).
const sonarrRoute = '/sonarr';

/// Relative child paths (under [sonarrRoute]).
const sonarrSeriesChildPath = 'series/:id';
const sonarrAddChildPath = 'add';

/// The series id of a deep link: a plain positive decimal number that fits
/// 32 bits, otherwise `null`. No sign, spaces, hex or leading zeros.
int? parseSeriesId(String? raw) {
  if (raw == null || !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(raw)) return null;
  final id = int.parse(raw);
  return id <= 0x7fffffff ? id : null;
}

/// In-app deep link to a series (NAV-05): `/sonarr/series/<id>`.
String sonarrSeriesLocation(int id) => '$sonarrRoute/series/$id';

/// In-app link to the add flow, optionally with a search term.
String sonarrAddLocation({String? term}) => term == null || term.isEmpty
    ? '$sonarrRoute/add'
    : Uri(path: '$sonarrRoute/add', queryParameters: {'term': term}).toString();

/// The detail and add screens, as child routes of the Sonarr destination.
///
/// Both are full-screen flows above the shell.
final List<RouteBase> sonarrChildRoutes = [
  GoRoute(
    path: sonarrSeriesChildPath,
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) {
      final id = parseSeriesId(state.pathParameters['id']);
      // A malformed id never reaches the server: it is "not found" at once.
      return id == null
          ? const SeriesNotFoundScreen()
          : SeriesDetailScreen(seriesId: id);
    },
  ),
  GoRoute(
    path: sonarrAddChildPath,
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) =>
        AddSeriesScreen(initialTerm: state.uri.queryParameters['term']),
  ),
];

/// Sonarr tab: offered once a Sonarr server exists.
final sonarrDestination = AppDestination(
  id: 'sonarr',
  route: sonarrRoute,
  icon: Icons.tv_outlined,
  selectedIcon: Icons.tv,
  label: (l10n) => l10n.navSonarr,
  kinds: const {ServiceKind.sonarr},
  screen: ScreenName.sonarrLibrary,
  switcherKind: ServiceKind.sonarr,
  children: sonarrChildRoutes,
  builder: (context, state) => const SonarrHomeScreen(),
);
