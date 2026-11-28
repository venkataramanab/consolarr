// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_screen.dart';
import 'package:consolarr/features/radarr/radarr_routes.dart' show parseMovieId;
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart'
    show parseSeriesId, sonarrSeriesChildPath, sonarrSeriesLocation;
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart' show PosterCard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'screen_support.dart';
import 'support.dart';

/// Routes at the real paths (see `sonarr_routes.dart`, `radarr_routes.dart`
/// and `torrents_routes.dart`) with stub pages that show where they landed.
GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(body: DashboardScreen()),
    ),
    GoRoute(
      path: '/sonarr',
      builder: (context, state) => const Text('Sonarr tab'),
      routes: [
        GoRoute(
          path: sonarrSeriesChildPath,
          builder: (context, state) =>
              Text('series ${parseSeriesId(state.pathParameters['id'])}'),
        ),
      ],
    ),
    GoRoute(
      path: '/radarr',
      builder: (context, state) => const Text('Radarr tab'),
      routes: [
        GoRoute(
          path: 'movie/:id',
          builder: (context, state) =>
              Text('movie ${parseMovieId(state.pathParameters['id'])}'),
        ),
      ],
    ),
    GoRoute(path: '/torrents', builder: (_, _) => const Text('Torrents tab')),
    GoRoute(path: '/onboarding', builder: (_, _) => const Text('Onboarding')),
    GoRoute(path: '/about', builder: (_, _) => const Text('About')),
  ],
);

void main() {
  final server = FakeServer();
  final sonarr = connection(ServiceKind.sonarr, 's', server);
  final radarr = connection(ServiceKind.radarr, 'r', server);
  final torrent = connection(ServiceKind.qbittorrent, 't', server);

  final variant = HarnessVariant(
    size: const Size(412, 915),
    textScale: 1,
    locale: const Locale('en'),
    brightness: Brightness.dark,
  );

  late Env env;
  late GoRouter router;
  setUp(() {
    env = Env();
    router = _router();
  });
  tearDown(() => router.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required Map<ServiceKind, Object?> connections,
    required Map<ServiceKind, CountingSource> sources,
    bool noServers = false,
  }) async {
    applyVariantView(tester, variant);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...env.overrides(
            sources: {for (final e in sources.entries) e.key: e.value.source},
          ),
          activeConnections.overrideWith(() => SeededConnections(connections)),
          uiServersProvider.overrideWithValue(
            AsyncData([
              if (!noServers)
                ServerEntry(profile: sonarr.profile, sortOrder: 0),
            ]),
          ),
          appLockedProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> opened() => [
    for (final e in env.analytics.events)
      if (e.name == 'dashboard_card_opened')
        '${e.parameters['card']}:${e.parameters['destination']}',
  ];

  testWidgets('an upcoming episode opens its series, and back returns', (
    tester,
  ) async {
    await pump(
      tester,
      connections: {ServiceKind.sonarr: sonarr},
      sources: {
        ServiceKind.sonarr: CountingSource(
          upcoming: Result.ok([
            mediaItem(
              'ep:1',
              from: sonarr,
              day: DateTime.utc(2026, 3, 11),
              season: 1,
              episode: 1,
            ),
          ]),
        ),
      },
    );
    await tester.tap(find.byType(PosterCard).first);
    await tester.pumpAndSettle();
    expect(find.text('series 1'), findsOneWidget);
    expect(opened(), ['upcoming:series']);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('a recent movie opens its detail', (tester) async {
    final item = MediaItem(
      id: 'hist:1',
      title: 'Example Movie',
      dio: radarr.dio,
      at: fixedNow,
      link: const DashboardLink(
        '/radarr/movie/41',
        DashboardTarget.detail,
        DashboardDestination.movie,
      ),
    );
    await pump(
      tester,
      connections: {ServiceKind.radarr: radarr},
      sources: {
        ServiceKind.radarr: CountingSource(recent: Result.ok([item])),
      },
    );
    await tester.tap(find.text('Example Movie'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('movie 41'), findsOneWidget);
    expect(opened(), ['recent:movie']);
  });

  testWidgets('the activity summary opens the service tab', (tester) async {
    await pump(
      tester,
      connections: {
        ServiceKind.sonarr: sonarr,
        ServiceKind.qbittorrent: torrent,
      },
      sources: {
        ServiceKind.sonarr: CountingSource(),
        ServiceKind.qbittorrent: CountingSource(
          activity: const Result.ok(
            ActivitySummary(
              active: 1,
              attention: 0,
              rows: [],
              link: DashboardLink(
                '/torrents',
                DashboardTarget.tab,
                DashboardDestination.torrents,
              ),
            ),
          ),
          feedsMedia: false,
        ),
      },
    );
    await tester.tap(
      find.textContaining('qBittorrent').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Torrents tab'), findsOneWidget);
    expect(opened(), ['activity:torrents']);
  });

  testWidgets('the setup prompt and the about button navigate', (tester) async {
    await pump(
      tester,
      connections: {ServiceKind.sonarr: null},
      sources: {ServiceKind.sonarr: CountingSource()},
      noServers: true,
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Onboarding'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
  });

  test('every link the sources build is one the detail routes accept', () {
    expect(parseSeriesId('7'), 7);
    expect(sonarrSeriesLocation(7), '/sonarr/series/7');
    expect(parseMovieId('41'), 41);
    // A deleted or malformed id reaches the detail screen's "no longer
    // exists" state, never the server (covered by the Sonarr and Radarr
    // detail tests).
    expect(parseSeriesId('0'), isNull);
    expect(parseMovieId('abc'), isNull);
  });
}
