// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/radarr_routes.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';
import 'switching.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

GoRouter _router(String location) {
  final router = buildRouter(
    initialLocation: location,
    destinations: [
      AppDestination(
        id: 'home',
        route: '/',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: (l) => l.navHome,
        builder: (context, state) => const Text('home'),
      ),
      radarrDestination,
    ],
  );
  addTearDown(router.dispose);
  return router;
}

Widget _app(GoRouter router, FakeRadarrApi api) => ProviderScope(
  overrides: radarrOverrides(api),
  child: harnessApp(
    _v,
    ConsolarrEffectsScope(
      reduceMotion: true,
      child: Router<Object>(
        routerDelegate: router.routerDelegate,
        routeInformationParser: router.routeInformationParser,
        routeInformationProvider: router.routeInformationProvider,
        backButtonDispatcher: RootBackButtonDispatcher(),
      ),
    ),
  ),
);

void main() {
  Future<void> open(
    WidgetTester tester,
    String location,
    FakeRadarrApi api,
  ) async {
    applyVariantView(tester, _v);
    await tester.pumpWidget(_app(_router(location), api));
    await tester.pumpAndSettle();
  }

  testWidgets('a deep link opens the movie', (tester) async {
    final api = FakeRadarrApi(
      moviesResult: Result.ok([fakeMovie(7, title: 'Linked Movie')]),
    );
    await open(tester, '/radarr/movie/7', api);
    expect(find.text('Linked Movie'), findsWidgets);
  });

  testWidgets('a deleted movie says it no longer exists', (tester) async {
    final api = FakeRadarrApi()
      ..movieResult = const Result.err(AppError(ErrorCategory.notFound));
    await open(tester, '/radarr/movie/999', api);
    expect(find.text('This movie no longer exists'), findsOneWidget);
  });

  for (final id in ['abc', '0', '-1', '01', '1.5', '2147483648']) {
    testWidgets('the id "$id" is "gone" at once, without any request', (
      tester,
    ) async {
      final api = GatedApi(moviesResult: Result.ok([fakeMovie(7)]))
        ..movieResult = Result.ok(fakeMovie(7));
      await open(tester, '/radarr/movie/$id', api);
      expect(find.text('This movie no longer exists'), findsOneWidget);
      expect(api.movieCalls, 0);
      expect(api.moviesCalls, 0);
    });
  }

  testWidgets('the add flow takes the term from the link', (tester) async {
    final api = FakeRadarrApi()
      ..lookupResult = Result.ok([
        const RadarrMovie(
          id: 0,
          title: 'Found Movie',
          sortTitle: 'f',
          tmdbId: 1,
        ),
      ]);
    await open(tester, '/radarr/add?term=found', api);
    expect(api.calls, ['lookup found']);
    expect(find.text('Found Movie'), findsOneWidget);
  });
}
