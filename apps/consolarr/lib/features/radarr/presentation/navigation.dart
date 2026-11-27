// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

// Detail and add are full-screen child routes of the Radarr branch
// (`radarr_routes.dart`), so deep links (NAV-05) and back work. Without a
// router (a screen pumped on its own in a test) they fall back to a pushed
// route.

/// The Radarr branch route; mirrors `radarrRoute` (kept here to avoid an
/// import cycle with the screens).
const radarrBase = '/radarr';

/// Opens the movie with [id] above the shell.
Future<void> openMovie(BuildContext context, int id) {
  final router = GoRouter.maybeOf(context);
  if (router != null) return router.push<void>('$radarrBase/movie/$id');
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'radarr/movie'),
      builder: (_) => MovieDetailScreen(movieId: id),
    ),
  );
}

/// Opens the add-movie flow, optionally with [term] already searched.
Future<void> openAddMovie(BuildContext context, {String? term}) {
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    return router.push<void>(
      Uri(
        path: '$radarrBase/add',
        queryParameters: term == null ? null : {'term': term},
      ).toString(),
    );
  }
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'radarr/add'),
      builder: (_) => AddMovieScreen(initialTerm: term),
    ),
  );
}
