// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:consolarr/features/radarr/presentation/radarr_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:core/core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the Radarr area.
const radarrRoute = '/radarr';

/// Radarr tab: offered once a Radarr server exists.
///
/// Detail and add are full-screen child routes (paths relative to
/// [radarrRoute]); an id that is not a number lands on the "no longer exists"
/// state like a deleted movie (NAV-05).
final radarrDestination = AppDestination(
  id: 'radarr',
  route: radarrRoute,
  icon: Icons.movie_outlined,
  selectedIcon: Icons.movie,
  label: (l10n) => l10n.navRadarr,
  kinds: const {ServiceKind.radarr},
  screen: ScreenName.radarrLibrary,
  switcherKind: ServiceKind.radarr,
  builder: (context, state) => const RadarrScreen(),
  children: [
    GoRoute(
      path: 'movie/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => MovieDetailScreen(
        // An unparsable id can never exist: -1 resolves to "not found".
        movieId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
      ),
    ),
    GoRoute(
      path: 'add',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          AddMovieScreen(initialTerm: state.uri.queryParameters['term']),
    ),
  ],
);
