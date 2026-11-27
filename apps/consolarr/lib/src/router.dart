// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/features/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route paths.
abstract final class AppRoutes {
  static const home = '/';
  static const about = '/about';
}

/// Builds the app router. Exposed for tests.
GoRouter buildRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
    ],
  );
}

/// The router, created lazily on first read (the first frame).
final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
});
