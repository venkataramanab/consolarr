// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:material_ui/material_ui.dart';

// Detail, add and search are full-screen flows pushed on the root navigator.
// TODO(w4d): move them to `AppDestination.children` routes (deep links,
// NAV-05) once `AppDestination.children` is on `main`; the screens already
// take only an id / search term, so only these two functions change.

/// Opens the movie with [id] above the shell.
Future<void> openMovie(BuildContext context, int id) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'radarr/movie'),
        builder: (_) => MovieDetailScreen(movieId: id),
      ),
    );

/// Opens the add-movie flow, optionally with [term] already searched.
Future<void> openAddMovie(BuildContext context, {String? term}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'radarr/add'),
        builder: (_) => AddMovieScreen(initialTerm: term),
      ),
    );
