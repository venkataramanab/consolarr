// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/navigation/destinations.dart';
import 'package:consolarr/src/router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../servers/ui/support.dart';

/// Destinations with stub screens built on the real top bar scaffold, so the
/// shell, the floating nav bar and the scaffold are exercised together.
AppDestination _stub(
  String id,
  String Function(AppLocalizations) label,
  IconData icon, {
  Set<ServiceKind>? kinds,
}) => AppDestination(
  id: id,
  route: id == 'home' ? '/' : '/$id',
  icon: icon,
  selectedIcon: icon,
  label: label,
  kinds: kinds,
  builder: (context, state) => FloatingTopBarScaffold(
    title: 'Screen $id',
    bodyBuilder: (context, padding) => ListView(
      padding: padding,
      children: [
        for (var i = 0; i < 30; i++) ListTile(title: Text('Row $i of $id')),
      ],
    ),
  ),
);

List<AppDestination> _destinations() => [
  _stub('home', (l) => l.navHome, Icons.home_outlined),
  _stub(
    'sonarr',
    (l) => l.navSonarr,
    Icons.tv_outlined,
    kinds: {ServiceKind.sonarr},
  ),
  _stub(
    'torrents',
    (l) => l.navTorrents,
    Icons.download_outlined,
    kinds: {ServiceKind.qbittorrent, ServiceKind.transmission},
  ),
  _stub('servers', (l) => l.navServers, Icons.dns_outlined),
];

Widget _app(
  HarnessVariant v, {
  required String location,
  List<ServerEntry> servers = const [],
}) {
  final router = buildRouter(
    initialLocation: location,
    destinations: _destinations(),
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [uiServersProvider.overrideWithValue(AsyncData(servers))],
    child: harnessApp(
      v,
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
}

ServerEntry _server(String id, ServiceKind kind) =>
    entry(id, kind: kind, name: 'Example $id');

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

final _stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

void main() {
  group('visible destinations', () {
    final all = _destinations();

    test('only the always-offered ones without servers', () {
      expect(
        visibleDestinationIndices(const [], currentIndex: 0, destinations: all),
        [0, 3],
      );
    });

    test('a service appears once a server of any of its kinds exists', () {
      expect(
        visibleDestinationIndices(
          [_server('a', ServiceKind.transmission)],
          currentIndex: 0,
          destinations: all,
        ),
        [0, 2, 3],
      );
    });

    test('the open branch is always shown (no highlight on another tab)', () {
      expect(
        visibleDestinationIndices(const [], currentIndex: 1, destinations: all),
        [0, 1, 3],
      );
    });

    test('routeForKind finds the destination that serves a kind', () {
      expect(routeForKind(ServiceKind.sonarr, destinations: all), '/sonarr');
      expect(
        routeForKind(ServiceKind.transmission, destinations: all),
        '/torrents',
      );
      expect(routeForKind(ServiceKind.radarr, destinations: all), isNull);
    });

    test('the real destinations are consistent', () {
      expect({
        for (final d in appDestinations) d.id,
      }, hasLength(appDestinations.length));
      expect({
        for (final d in appDestinations) d.route,
      }, hasLength(appDestinations.length));
      expect(appDestinations.first.route, '/');
      expect({
        for (final d in appDestinations) ...?d.kinds,
      }, containsAll([ServiceKind.sonarr, ServiceKind.qbittorrent]));
      expect(routeForKind(ServiceKind.sonarr), '/sonarr');
      expect(routeForKind(ServiceKind.qbittorrent), '/torrents');
    });
  });

  group('shell', () {
    testWidgets('the bar highlights the open destination, not Home, even '
        'without a server of that kind', (tester) async {
      applyVariantView(tester, _v);
      await tester.pumpWidget(_app(_v, location: '/sonarr'));
      await tester.pumpAndSettle();
      expect(find.text('Screen sonarr'), findsOneWidget);
      final bar = tester.widget<FloatingNavBar>(find.byType(FloatingNavBar));
      expect(bar.destinations.map((d) => d.label), [
        'Home',
        'Series',
        'Settings',
        'Servers',
      ]);
      expect(bar.selectedIndex, 1);
    });

    testWidgets('tapping a tab switches the branch', (tester) async {
      applyVariantView(tester, _v);
      await tester.pumpWidget(
        _app(_v, location: '/', servers: [_server('a', ServiceKind.sonarr)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Screen home'), findsOneWidget);
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.text('Screen sonarr'), findsOneWidget);
      expect(
        tester
            .widget<FloatingNavBar>(find.byType(FloatingNavBar))
            .selectedIndex,
        1,
      );
    });

    testWidgets('no overflow across the full matrix', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _app(
          v,
          location: '/sonarr',
          servers: [
            _server('a', ServiceKind.sonarr),
            _server('b', ServiceKind.qbittorrent),
          ],
        ),
      );
    });

    testWidgets('accessible at 320x568, scale 2.0, ar and en_XA', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => _app(
          v,
          location: '/',
          servers: [
            _server('a', ServiceKind.sonarr),
            _server('b', ServiceKind.qbittorrent),
          ],
        ),
        variants: _stress,
        verify: (v) => expectAccessible(tester),
      );
    });

    testWidgets('accessible in en at scale 1.0', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _app(v, location: '/servers'),
        variants: harnessMatrix(textScales: [1], locales: [const Locale('en')]),
        verify: (v) => expectAccessible(tester),
      );
    });

    testWidgets('system back from another tab returns to Home first', (
      tester,
    ) async {
      applyVariantView(tester, _v);
      await tester.pumpWidget(_app(_v, location: '/servers'));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(FloatingNavBar));
      expect(GoRouter.of(element).state.uri.path, '/servers');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Screen home'), findsOneWidget);
    });
  });
}
