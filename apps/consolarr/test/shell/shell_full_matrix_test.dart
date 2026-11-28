// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  _stub('home', (l) => l.navDashboard, Icons.home_outlined),
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

List<ServerEntry> get _servers => [
  _server('a', ServiceKind.sonarr),
  _server('b', ServiceKind.qbittorrent),
];

/// 2 sizes x 2 text scales x 3 locales x 2 themes = 24 variants.
final _full = harnessMatrix(sizes: const [Size(320, 568), Size(412, 915)]);

void main() {
  for (final location in ['/', '/sonarr', '/servers']) {
    testWidgets('with servers at $location: full matrix, no overflow and '
        'accessible', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _app(v, location: location, servers: _servers),
        variants: _full,
        verify: (v) => expectAccessible(tester),
      );
    });
  }

  testWidgets('without servers: full matrix, no overflow and accessible', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => _app(v, location: '/'),
      variants: _full,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('golden: shell with nav bar (ar, dark, 320x568, scale 2.0)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(320, 568),
      textScale: 2,
      locale: Locale('ar'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(_app(v, location: '/', servers: _servers));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/shell_nav_ar_dark_320x568_x2.png'),
    );
  });
}
