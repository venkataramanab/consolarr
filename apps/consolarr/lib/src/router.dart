// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/features/home/home_routes.dart';
import 'package:consolarr/features/servers/presentation/onboarding_screen.dart';
import 'package:consolarr/features/servers/presentation/server_editor_screen.dart';
import 'package:consolarr/features/servers/presentation/servers_routes.dart';
import 'package:consolarr/features/shell/presentation/app_shell.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/features/torrents/torrents_routes.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/navigation/destinations.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route paths of the flows above the shell. The shell's own branches are
/// described by `appDestinations` (see `lib/src/navigation`).
abstract final class AppRoutes {
  static const home = homeRoute;
  static const sonarr = sonarrRoute;
  static const torrents = torrentsRoute;
  static const servers = ServersRoutes.list;
  static const serverNew = '/servers/new';
  static String serverEdit(String id) => '/servers/${Uri.encodeComponent(id)}';
  static const onboarding = '/onboarding';
  static const about = '/about';
}

/// Builds the app router. Exposed for tests. The shell branches come from
/// [destinations] (default: `appDestinations`), in that order.
GoRouter buildRouter({
  String initialLocation = AppRoutes.home,
  List<AppDestination>? destinations,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          for (final d in destinations ?? appDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(path: d.route, builder: d.builder, routes: d.children),
              ],
            ),
        ],
      ),
      // Full-screen flows above the shell: the editor hides the bar so the
      // secure-flagged form has the whole window.
      GoRoute(
        path: AppRoutes.serverNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ServerEditorScreen(
          initialKind: _kindFrom(state.uri.queryParameters['kind']),
        ),
      ),
      GoRoute(
        path: '/servers/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            ServerEditorScreen(serverId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AboutScreen(),
      ),
    ],
    navigatorKey: rootNavigatorKey,
  );
}

ServiceKind? _kindFrom(String? name) {
  if (name == null) return null;
  for (final k in ServiceKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// The router, created lazily on first read (the first frame).
final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
});
