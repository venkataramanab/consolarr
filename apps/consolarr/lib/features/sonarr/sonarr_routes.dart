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
    builder: (context, state) => SeriesDetailScreen(
      seriesId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
    ),
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
