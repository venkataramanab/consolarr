// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/navigation/destinations.dart';
import 'package:consolarr/src/router.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

Widget _screen(String text) => FloatingTopBarScaffold(
  title: text,
  bodyBuilder: (context, padding) =>
      ListView(padding: padding, children: [Text(text)]),
);

List<AppDestination> _destinations() => [
  AppDestination(
    id: 'home',
    route: '/',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: (l) => l.navDashboard,
    builder: (context, state) => _screen('Screen home'),
  ),
  AppDestination(
    id: 'things',
    route: '/things',
    icon: Icons.tv_outlined,
    selectedIcon: Icons.tv,
    label: (l) => l.navServers,
    builder: (context, state) => _screen('Screen things'),
    children: [
      GoRoute(
        path: 'inner/:id',
        builder: (context, state) =>
            _screen('Inner ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: 'full',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => _screen('Full screen'),
      ),
    ],
  ),
];

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

GoRouter _router(String location) {
  final router = buildRouter(
    initialLocation: location,
    destinations: _destinations(),
  );
  addTearDown(router.dispose);
  return router;
}

Widget _app(GoRouter router) => ProviderScope(
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
  testWidgets('a child route resolves under its branch, bar visible', (
    tester,
  ) async {
    applyVariantView(tester, _v);
    final router = _router('/things/inner/7');
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    expect(find.text('Inner 7'), findsWidgets);
    expect(find.byType(FloatingNavBar), findsOneWidget);
  });

  testWidgets('a child route with the root navigator key hides the bar', (
    tester,
  ) async {
    applyVariantView(tester, _v);
    final router = _router('/things/full');
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    expect(find.text('Full screen'), findsWidgets);
    expect(find.byType(FloatingNavBar), findsNothing);
  });

  testWidgets('back pops the child first, then goes Home at the branch root', (
    tester,
  ) async {
    applyVariantView(tester, _v);
    final router = _router('/things');
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    router.push('/things/inner/1');
    await tester.pumpAndSettle();
    expect(find.text('Inner 1'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Inner 1'), findsNothing);
    expect(find.text('Screen things'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Screen home'), findsWidgets);
  });

  test('visibleDestinationIndices is unchanged by children', () {
    expect(
      visibleDestinationIndices(
        const [],
        currentIndex: 0,
        destinations: _destinations(),
      ),
      [0, 1],
    );
  });
}
