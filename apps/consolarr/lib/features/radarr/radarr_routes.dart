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

/// The movie id of a deep link: a plain positive decimal number that fits 32
/// bits, otherwise `null`. No sign, spaces, hex or leading zeros.
int? parseMovieId(String? raw) {
  if (raw == null || !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(raw)) return null;
  final id = int.parse(raw);
  return id <= 0x7fffffff ? id : null;
}

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
        // An id that can never exist (not a positive 32-bit number) is
        // "no longer exists" at once: -1 never reaches the server.
        movieId: parseMovieId(state.pathParameters['id']) ?? -1,
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
