// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_screen.dart';
import 'package:consolarr/features/dashboard/presentation/media_carousel.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:test_harness/test_harness.dart';

import 'screen_support.dart';
import 'support.dart';

const _all = [
  ServiceKind.sonarr,
  ServiceKind.radarr,
  ServiceKind.qbittorrent,
  ServiceKind.transmission,
  ServiceKind.deluge,
];

/// Runs [scenario] under the full matrix of the brief (320x568 and 412x915,
/// en / en_XA / ar, scale 1.0 and 2.0, dark and light) with every
/// accessibility guideline, then once more in a reference variant for
/// [check].
class Scenario {
  Scenario(
    this.name, {
    required this.connections,
    required this.sources,
    this.noServers = false,
    this.check,
    this.prepare,
  });

  final String name;
  final Map<ServiceKind, Object?> connections;
  final Map<ServiceKind, DashboardSource> sources;
  final bool noServers;
  final Future<void> Function(WidgetTester tester, AppLocalizations l10n)?
  check;
  final void Function(Env env)? prepare;
}

Map<ServiceKind, DashboardSource> _same(
  CountingSource s, [
  Set<ServiceKind>? kinds,
]) => {
  for (final k in kinds ?? _all.toSet())
    k: (k == ServiceKind.sonarr || k == ServiceKind.radarr)
        ? s.source
        : CountingSource(activity: s.activity, feedsMedia: false).source,
};

void main() {
  final server = FakeServer();
  ServerConnection c(ServiceKind kind, [String? id]) =>
      connection(kind, id ?? kind.name, server, name: 'Server ${kind.name}');

  List<MediaItem> upcoming(
    ServerConnection from,
    int n, {
    String title = 'Example Show',
  }) => [
    for (var i = 1; i <= n; i++)
      mediaItem(
        'ep:$i',
        title: n == 1 ? title : '$title $i',
        from: from,
        day: DateTime.utc(2026, 3, 10 + i % 10),
        season: 1 + i % 3,
        episode: i,
      ),
  ];

  List<MediaItem> recent(
    ServerConnection from,
    int n, {
    String title = 'Example Show',
  }) => [
    for (var i = 1; i <= n; i++)
      mediaItem(
        'hist:$i',
        title: n == 1 ? title : '$title $i',
        from: from,
        at: fixedNow.subtract(Duration(minutes: 7 * i)),
        season: i.isEven ? 1 : null,
        episode: i.isEven ? i : null,
      ),
  ];

  Future<void> expectFullMatrix(
    WidgetTester tester,
    Env env,
    Scenario s,
  ) async {
    await pumpMatrix(
      tester,
      (v) {
        s.prepare?.call(env);
        return dashboardApp(
          v,
          env,
          connections: s.connections,
          sources: s.sources,
          noServers: s.noServers,
        );
      },
      variants: briefMatrix(),
      verify: (v) async {
        try {
          await expectAccessible(tester);
          if (!s.noServers) {
            // The list is lazy: on a small display the last card is not built
            // until it is scrolled to. Bring the Recent card fully into view
            // and check the structure of what is there (tap targets, labels).
            // The contrast guideline is not repeated here: with cards under
            // the translucent top bar it reads the bar, not the text, and the
            // first run above has already read every card that was built.
            final recent = find.byType(RecentCard);
            await tester.scrollUntilVisible(
              recent,
              300,
              scrollable: find
                  .descendant(
                    of: find.byType(DashboardScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.ensureVisible(recent);
            await tester.pump();
            expect(recent, findsOneWidget, reason: 'the Recent card is built');
            await expectTapTargets(tester);
            await expectLabeledTapTargets(tester);
          }
        } on TestFailure catch (e) {
          fail('${s.name} @ ${v.label}: $e');
        }
      },
    );
    if (s.check != null) {
      // Tall enough that every card is built (the list is lazy).
      final v = HarnessVariant(
        size: const Size(412, 3000),
        textScale: 1,
        locale: const Locale('en'),
        brightness: Brightness.dark,
      );
      applyVariantView(tester, v);
      s.prepare?.call(env);
      await tester.pumpWidget(
        dashboardApp(
          v,
          env,
          connections: s.connections,
          sources: s.sources,
          noServers: s.noServers,
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await s.check!(tester, l10n);
    }
  }

  final scenarios = <Scenario>[];
  final sonarr = c(ServiceKind.sonarr);
  final radarr = c(ServiceKind.radarr);

  CountingSource healthy({int items = 3, bool torrentSpeeds = false}) =>
      CountingSource(
        activity: Result.ok(
          summary(
            down: torrentSpeeds ? 1536 * 1024 : null,
            up: torrentSpeeds ? 512 * 1024 : null,
          ),
        ),
        upcoming: Result.ok(upcoming(sonarr, items)),
        recent: Result.ok(recent(sonarr, items)),
      );

  scenarios
    ..add(
      Scenario(
        'loading: every card is a static skeleton',
        connections: {for (final k in _all) k: Completer<ServerConnection?>()},
        sources: _same(healthy()),
        check: (tester, l10n) async {
          expect(
            find.bySemanticsLabel(l10n.dashboardLoading),
            findsNWidgets(3),
          );
          expect(find.byType(PosterCard), findsNothing);
        },
      ),
    )
    ..add(
      Scenario(
        'no servers at all: one setup prompt',
        connections: {for (final k in _all) k: null},
        sources: _same(healthy()),
        noServers: true,
        check: (tester, l10n) async {
          expect(find.text(l10n.dashboardEmptyHeading), findsOneWidget);
          expect(find.text(l10n.dashboardSetupCta), findsOneWidget);
          expect(find.text(l10n.dashboardActivityHeading), findsNothing);
        },
      ),
    )
    ..add(
      Scenario(
        'only a torrent client: media cards name what to set up',
        connections: {
          for (final k in _all) k: k == ServiceKind.qbittorrent ? c(k) : null,
        },
        sources: _same(healthy(torrentSpeeds: true)),
        check: (tester, l10n) async {
          expect(
            find.text(l10n.dashboardUpcomingNotConfigured),
            findsOneWidget,
          );
          expect(find.text(l10n.dashboardRecentNotConfigured), findsOneWidget);
          expect(find.text(l10n.dashboardSetupCta), findsNWidgets(2));
          expect(find.textContaining('qBittorrent'), findsWidgets);
        },
      ),
    )
    ..add(
      Scenario(
        'nothing configured for the cards',
        connections: {for (final k in _all) k: null},
        sources: _same(healthy()),
        check: (tester, l10n) async {
          expect(
            find.text(l10n.dashboardActivityNotConfigured),
            findsOneWidget,
          );
          expect(
            find.text(l10n.dashboardUpcomingNotConfigured),
            findsOneWidget,
          );
          expect(find.text(l10n.dashboardRecentNotConfigured), findsOneWidget);
        },
      ),
    )
    ..add(
      Scenario(
        'data: all five kinds configured',
        connections: {for (final k in _all) k: c(k)},
        sources: _same(healthy(torrentSpeeds: true)),
        check: (tester, l10n) async {
          expect(find.textContaining('Sonarr'), findsWidgets);
          expect(find.textContaining('Radarr'), findsWidgets);
          expect(find.textContaining('qBittorrent'), findsWidgets);
          expect(find.textContaining('Transmission'), findsWidgets);
          expect(find.textContaining('Deluge'), findsWidgets);
          expect(find.textContaining('MB/'), findsWidgets);
        },
      ),
    )
    ..add(
      Scenario(
        'empty: nothing downloading, coming up or recent',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {
          ServiceKind.sonarr: CountingSource(
            activity: Result.ok(summary(active: 0, rows: [])),
          ).source,
        },
        check: (tester, l10n) async {
          expect(find.text(l10n.dashboardActivityEmptyHeading), findsOneWidget);
          expect(find.text(l10n.dashboardUpcomingEmptyHeading), findsOneWidget);
          expect(find.text(l10n.dashboardRecentEmptyHeading), findsOneWidget);
          // "nothing exists" is not "everything failed"
          expect(find.text(l10n.dashboardRetry), findsNothing);
        },
      ),
    )
    ..add(
      Scenario(
        'partial: one service down, the rest of the card stays',
        connections: {for (final k in _all) k: c(k)},
        sources: {
          ..._same(healthy()),
          ServiceKind.radarr: CountingSource(
            activity: const Result.err(AppError(ErrorCategory.serverError)),
            upcoming: const Result.err(AppError(ErrorCategory.serverError)),
            recent: Result.ok(recent(radarr, 2)),
          ).source,
        },
        check: (tester, l10n) async {
          // the service and the server's name, each on its own line
          expect(find.text('Server radarr'), findsNWidgets(2));
          expect(find.text(l10n.dashboardRetry), findsNWidgets(2));
          // the healthy services are still there
          expect(find.textContaining('Sonarr'), findsWidgets);
          expect(find.byType(PosterCard), findsWidgets);
        },
      ),
    );

  for (final category in [
    ErrorCategory.authFailed,
    ErrorCategory.networkUnreachable,
    ErrorCategory.timeout,
    ErrorCategory.serverError,
    ErrorCategory.unsupportedVersion,
    ErrorCategory.parseError,
  ]) {
    final failing = CountingSource(
      activity: Result.err(AppError(category)),
      upcoming: Result.err(AppError(category)),
      recent: Result.err(AppError(category)),
    );
    scenarios.add(
      Scenario(
        'error ${category.code}: names the service, says why and offers retry',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {ServiceKind.sonarr: failing.source},
        check: (tester, l10n) async {
          expect(find.text('Server sonarr'), findsNWidgets(3));
          // the copy of the category, not a blanket "not available"
          final copy = connectionErrorMessage(l10n, AppError(category));
          expect(find.text(copy.message), findsNWidgets(3));
          expect(find.text(l10n.dashboardRetry), findsNWidgets(3));
          final upcomingBefore = failing.calls[DashboardCard.upcoming]!;
          final activityBefore = failing.calls[DashboardCard.activity]!;
          await tester.tap(find.text(l10n.dashboardRetry).at(1));
          await tester.pumpAndSettle();
          expect(failing.calls[DashboardCard.upcoming], upcomingBefore + 1);
          expect(
            failing.calls[DashboardCard.activity],
            activityBefore,
            reason: 'retry asks only the card it was tapped on',
          );
        },
      ),
    );
  }

  scenarios
    ..add(
      Scenario(
        'missing credentials: the error is on the card, the others stay',
        connections: {
          ServiceKind.sonarr: const AppError(
            ErrorCategory.authFailed,
            debugDetail: 'needs_credentials',
          ),
          ServiceKind.radarr: radarr,
        },
        sources: {
          ServiceKind.sonarr: healthy().source,
          ServiceKind.radarr: healthy().source,
        },
        check: (tester, l10n) async {
          await tester.pumpAndSettle();
          // Retrying cannot supply the missing secrets: the editor can.
          expect(find.text(l10n.dashboardEditServer), findsWidgets);
          expect(find.text(l10n.dashboardRetry), findsNothing);
          expect(find.byType(PosterCard), findsWidgets);
        },
      ),
    )
    ..add(
      Scenario(
        'Deluge needs its host: a hint instead of a retry, never torrents prefs',
        connections: {ServiceKind.deluge: c(ServiceKind.deluge)},
        sources: {
          ServiceKind.deluge: CountingSource(
            activity: const Result.err(HostChoiceRequired()),
            feedsMedia: false,
          ).source,
        },
        check: (tester, l10n) async {
          expect(find.text(l10n.dashboardDelugeHostHint), findsOneWidget);
          expect(find.text(l10n.dashboardOpenTorrents), findsOneWidget);
          expect(find.text(l10n.dashboardRetry), findsNothing);
        },
      ),
    )
    ..add(
      Scenario(
        'all servers offline: failures on activity, saved copies under an age '
        'banner for upcoming and recent',
        connections: {ServiceKind.sonarr: sonarr, ServiceKind.radarr: radarr},
        sources: {
          for (final k in [ServiceKind.sonarr, ServiceKind.radarr])
            k: CountingSource(
              activity: const Result.err(
                AppError(ErrorCategory.networkUnreachable),
              ),
              upcoming: const Result.err(
                AppError(ErrorCategory.networkUnreachable),
              ),
              recent: const Result.err(
                AppError(ErrorCategory.networkUnreachable),
              ),
            ).source,
        },
        prepare: (env) {
          final at = fixedNow.subtract(const Duration(hours: 2));
          for (final (k, from) in [
            (ServiceKind.sonarr, sonarr),
            (ServiceKind.radarr, radarr),
          ]) {
            unawaited(
              env.dashboardCache.write(
                from.profile.id,
                DashboardCard.upcoming,
                upcoming(from, 4),
                at,
              ),
            );
            unawaited(
              env.dashboardCache.write(
                from.profile.id,
                DashboardCard.recent,
                recent(from, 4),
                at,
              ),
            );
            expect(k, isNotNull);
          }
        },
        check: (tester, l10n) async {
          expect(find.text(l10n.dashboardCachedMessage), findsNWidgets(4));
          expect(
            find.text(l10n.dashboardCachedAge(l10n.dashboardAgeHours(2))),
            findsNWidgets(4),
          );
          expect(
            find.text(l10n.dashboardRetry),
            findsNWidgets(2),
            reason: 'the live activity has no saved copy',
          );
        },
      ),
    );

  const longTitle =
      'A Very Long Example Title That Goes On And On Without Any Sensible '
      'Place To Stop Because Server Text Is Never Trusted To Be Short '
      'مسلسل تجريبي طويل جدا بعنوان لا ينتهي أبدا';
  scenarios
    ..add(
      Scenario(
        'extremes: long titles everywhere',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {
          ServiceKind.sonarr: CountingSource(
            activity: Result.ok(
              summary(
                rows: [
                  ActivityRow(
                    id: 'q:1',
                    title: longTitle,
                    state: ActivityState.downloading,
                    progress: 0.5,
                    sizeLeft: 123456789012,
                    eta: const Duration(days: 3, hours: 4),
                    speed: 987654321,
                  ),
                ],
              ),
            ),
            upcoming: Result.ok(upcoming(sonarr, 1, title: longTitle)),
            recent: Result.ok(recent(sonarr, 1, title: longTitle)),
          ).source,
        },
      ),
    )
    ..add(
      Scenario(
        'extremes: one carousel item',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {ServiceKind.sonarr: healthy(items: 1).source},
        check: (tester, l10n) async {
          expect(find.byType(PosterCard), findsNWidgets(2));
        },
      ),
    )
    ..add(
      Scenario(
        'extremes: 25 carousel items are built lazily',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {ServiceKind.sonarr: healthy(items: 25).source},
        check: (tester, l10n) async {
          expect(find.byType(PosterCard).evaluate().length, lessThan(14));
        },
      ),
    )
    ..add(
      Scenario(
        'extremes: 10,000 items in a carousel stay lazy',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {ServiceKind.sonarr: healthy(items: 10000).source},
        check: (tester, l10n) async {
          expect(find.byType(PosterCard).evaluate().length, lessThan(14));
        },
      ),
    )
    ..add(
      Scenario(
        'extremes: 0 source items',
        connections: {ServiceKind.sonarr: sonarr},
        sources: {
          ServiceKind.sonarr: CountingSource(
            activity: Result.ok(summary(active: 0, rows: [])),
          ).source,
        },
      ),
    );

  for (final s in scenarios) {
    testWidgets(s.name, (tester) async {
      await expectFullMatrix(tester, Env(), s);
    });
  }

  group('semantics', () {
    Future<void> pumpData(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      final env = Env();
      final v = HarnessVariant(
        size: const Size(412, 915),
        textScale: 1,
        locale: locale,
        brightness: Brightness.dark,
      );
      applyVariantView(tester, v);
      await tester.pumpWidget(
        dashboardApp(
          v,
          env,
          connections: {ServiceKind.sonarr: sonarr},
          sources: {ServiceKind.sonarr: healthy(items: 20).source},
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('one heading per card, plus the bar title', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpData(tester);
      // The order a screen reader walks the page in.
      final headings = [
        for (final n in tester.semantics.simulatedAccessibilityTraversal())
          if (n.flagsCollection.isHeader) n.label,
      ];
      expect(headings, [
        'Dashboard',
        'Activity',
        'Upcoming',
        'Recently downloaded',
      ]);
      handle.dispose();
    });

    testWidgets('carousel items have a name, a button role and a position', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpData(tester);
      final item = find
          .bySemanticsLabel(RegExp(r'Example Show 1, .*, item 1 of 20'))
          .first;
      expect(tester.getSemantics(item).flagsCollection.isButton, isTrue);
      expect(
        find.bySemanticsLabel(RegExp('Upcoming, 20 items')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the carousel mirrors in a right-to-left locale', (
      tester,
    ) async {
      await pumpData(tester);
      final ltr = tester.getTopLeft(find.byType(PosterCard).first).dx;
      expect(ltr, lessThan(100));
      await pumpData(tester, locale: const Locale('ar'));
      final rtl = tester.getTopRight(find.byType(PosterCard).first).dx;
      expect(rtl, greaterThan(300));
    });

    testWidgets('progress is read in words, not only as a bar', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpData(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'Example Show, Downloading, 42% done')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('speeds keep their unit together', (tester) async {
      final env = Env();
      final v = HarnessVariant(
        size: const Size(320, 568),
        textScale: 2,
        locale: const Locale('en'),
        brightness: Brightness.dark,
      );
      applyVariantView(tester, v);
      final torrent = c(ServiceKind.qbittorrent);
      await tester.pumpWidget(
        dashboardApp(
          v,
          env,
          connections: {ServiceKind.qbittorrent: torrent},
          sources: {
            ServiceKind.qbittorrent: CountingSource(
              activity: Result.ok(
                summary(down: 1536 * 1024 * 1024, up: 2 * 1024),
              ),
              feedsMedia: false,
            ).source,
          },
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.textContaining('Down '));
      expect(text.data, contains('/⁠s'));
      expect(text.data, contains(' GB'));
    });
  });

  group('artwork', () {
    testWidgets('is decoded at display size through the server\'s own Dio', (
      tester,
    ) async {
      final env = Env();
      final v = HarnessVariant(
        size: const Size(412, 915),
        textScale: 2,
        locale: const Locale('en'),
        brightness: Brightness.dark,
      );
      applyVariantView(tester, v);
      final art = Uri.parse('https://sonarr.example/MediaCover/1/poster.jpg');
      final item = MediaItem(
        id: 'ep:1',
        title: 'Example Show',
        link: kLink,
        dio: sonarr.dio,
        artwork: art,
        day: DateTime.utc(2026, 3, 11),
        season: 1,
        episode: 1,
      );
      await tester.pumpWidget(
        dashboardApp(
          v,
          env,
          connections: {ServiceKind.sonarr: sonarr},
          sources: {
            ServiceKind.sonarr: CountingSource(upcoming: Result.ok([item]))
                .source,
          },
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image).first);
      final provider = image.image as ResizeImage;
      // text scale 2.0 -> poster 192 px wide at device pixel ratio 1
      expect(provider.width, 192);
      expect(
        provider.imageProvider.runtimeType.toString(),
        'SecureNetworkImage',
      );
    });

    testWidgets('a missing or broken poster is a placeholder', (tester) async {
      final env = Env();
      final v = HarnessVariant(
        size: const Size(412, 915),
        textScale: 1,
        locale: const Locale('en'),
        brightness: Brightness.dark,
      );
      applyVariantView(tester, v);
      await tester.pumpWidget(
        dashboardApp(
          v,
          env,
          connections: {ServiceKind.sonarr: sonarr},
          sources: {ServiceKind.sonarr: healthy().source},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ArtworkPlaceholder), findsWidgets);
    });
  });
}
