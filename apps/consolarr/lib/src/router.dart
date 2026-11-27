// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/features/home/home_screen.dart';
import 'package:consolarr/features/servers/presentation/server_editor_screen.dart';
import 'package:consolarr/features/servers/presentation/servers_list_screen.dart';
import 'package:consolarr/features/servers/presentation/onboarding_screen.dart';
import 'package:consolarr/features/shell/presentation/app_shell.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_library_screen.dart';
import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route paths.
abstract final class AppRoutes {
  static const home = '/';
  static const sonarr = '/sonarr';
  static const torrents = '/torrents';
  static const servers = '/servers';
  static const serverNew = '/servers/new';
  static String serverEdit(String id) => '/servers/${Uri.encodeComponent(id)}';
  static const onboarding = '/onboarding';
  static const about = '/about';
}

/// Builds the app router. Exposed for tests.
GoRouter buildRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.sonarr,
                builder: (context, state) => const SonarrLibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.torrents,
                builder: (context, state) => const TorrentListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.servers,
                builder: (context, state) => const ServersListScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen flows above the shell: the editor hides the bar so the
      // secure-flagged form has the whole window.
      GoRoute(
        path: AppRoutes.serverNew,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ServerEditorScreen(
          initialKind: _kindFrom(state.uri.queryParameters['kind']),
        ),
      ),
      GoRoute(
        path: '/servers/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            ServerEditorScreen(serverId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const AboutScreen(),
      ),
    ],
    navigatorKey: _rootKey,
  );
}

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>();

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
