// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_screen.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'screen_support.dart';
import 'support.dart';

HarnessVariant _v(
  String locale,
  Brightness b,
  Size size, {
  double scale = 1,
  String? country,
}) => HarnessVariant(
  size: size,
  textScale: scale,
  locale: Locale(locale, country),
  brightness: b,
);

void main() {
  final server = FakeServer();
  final sonarr = connection(
    ServiceKind.sonarr,
    's',
    server,
    name: 'Living room',
  );
  final radarr = connection(ServiceKind.radarr, 'r', server, name: 'Movies');
  final torrent = connection(
    ServiceKind.qbittorrent,
    't',
    server,
    name: 'Seedbox',
  );

  MediaItem upcoming(int i, ServerConnection from) => mediaItem(
    'ep:$i',
    title: 'Example Show $i',
    from: from,
    day: DateTime.utc(2026, 3, 10 + i),
    season: 2,
    episode: i,
  );
  MediaItem recent(int i, ServerConnection from) => mediaItem(
    'hist:$i',
    title: 'Example Show $i',
    from: from,
    at: fixedNow.subtract(Duration(hours: i)),
    season: i.isEven ? 1 : null,
    episode: i.isEven ? i : null,
  );

  CountingSource healthy() => CountingSource(
    activity: Result.ok(summary(down: 1536 * 1024, up: 256 * 1024)),
    upcoming: Result.ok([for (var i = 1; i <= 4; i++) upcoming(i, sonarr)]),
    recent: Result.ok([for (var i = 1; i <= 4; i++) recent(i, sonarr)]),
  );

  Future<void> golden(
    WidgetTester tester,
    String name,
    HarnessVariant v, {
    required Map<ServiceKind, Object?> connections,
    required Map<ServiceKind, CountingSource> sources,
    bool noServers = false,
    Env? env,
    void Function(Env env)? prepare,
  }) async {
    final e = env ?? Env();
    prepare?.call(e);
    applyVariantView(tester, v);
    await tester.pumpWidget(
      dashboardApp(
        v,
        e,
        connections: connections,
        sources: {for (final s in sources.entries) s.key: s.value.source},
        noServers: noServers,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('golden: data, en, dark', (tester) async {
    await golden(
      tester,
      'dashboard_data_en_dark_412x915',
      _v('en', Brightness.dark, const Size(412, 915)),
      connections: {
        ServiceKind.sonarr: sonarr,
        ServiceKind.qbittorrent: torrent,
      },
      sources: {
        ServiceKind.sonarr: healthy(),
        ServiceKind.qbittorrent: healthy(),
      },
    );
  });

  testWidgets('golden: data, en, light', (tester) async {
    await golden(
      tester,
      'dashboard_data_en_light_412x915',
      _v('en', Brightness.light, const Size(412, 915)),
      connections: {ServiceKind.sonarr: sonarr},
      sources: {ServiceKind.sonarr: healthy()},
    );
  });

  testWidgets('golden: partial, one service down, en, dark', (tester) async {
    await golden(
      tester,
      'dashboard_partial_en_dark_360x800',
      _v('en', Brightness.dark, const Size(360, 800)),
      connections: {ServiceKind.sonarr: sonarr, ServiceKind.radarr: radarr},
      sources: {
        ServiceKind.sonarr: healthy(),
        ServiceKind.radarr: CountingSource(
          activity: const Result.err(AppError(ErrorCategory.authFailed)),
          upcoming: const Result.err(AppError(ErrorCategory.authFailed)),
          recent: const Result.err(AppError(ErrorCategory.authFailed)),
        ),
      },
    );
  });

  testWidgets('golden: offline with saved copies, en, light', (tester) async {
    final env = Env();
    await golden(
      tester,
      'dashboard_offline_en_light_360x800',
      _v('en', Brightness.light, const Size(360, 800)),
      env: env,
      prepare: (e) {
        final at = fixedNow.subtract(const Duration(hours: 3));
        unawaited(
          e.dashboardCache.write('s', DashboardCard.upcoming, [
            for (var i = 1; i <= 3; i++) upcoming(i, sonarr),
          ], at),
        );
        unawaited(
          e.dashboardCache.write('s', DashboardCard.recent, [
            for (var i = 1; i <= 3; i++) recent(i, sonarr),
          ], at),
        );
      },
      connections: {ServiceKind.sonarr: sonarr},
      sources: {
        ServiceKind.sonarr: CountingSource(
          activity: const Result.err(
            AppError(ErrorCategory.networkUnreachable),
          ),
          upcoming: const Result.err(
            AppError(ErrorCategory.networkUnreachable),
          ),
          recent: const Result.err(AppError(ErrorCategory.networkUnreachable)),
        ),
      },
    );
  });

  testWidgets('golden: loading, en_XA, dark', (tester) async {
    await golden(
      tester,
      'dashboard_loading_en_XA_dark_412x915',
      _v('en', Brightness.dark, const Size(412, 915), country: 'XA'),
      connections: {ServiceKind.sonarr: Completer<ServerConnection?>()},
      sources: {ServiceKind.sonarr: healthy()},
    );
  });

  testWidgets('golden: no servers, ar, light', (tester) async {
    await golden(
      tester,
      'dashboard_empty_ar_light_360x800',
      _v('ar', Brightness.light, const Size(360, 800)),
      connections: {ServiceKind.sonarr: null},
      sources: {ServiceKind.sonarr: healthy()},
      noServers: true,
    );
  });

  testWidgets('golden: data, ar, text 2.0, 320 wide, dark', (tester) async {
    await golden(
      tester,
      'dashboard_data_ar_dark_320x568_x2',
      _v('ar', Brightness.dark, const Size(320, 568), scale: 2),
      connections: {
        ServiceKind.sonarr: sonarr,
        ServiceKind.qbittorrent: torrent,
      },
      sources: {
        ServiceKind.sonarr: healthy(),
        ServiceKind.qbittorrent: healthy(),
      },
    );
  });

  testWidgets('golden: data, ar, text 2.0, 320 wide, light', (tester) async {
    await golden(
      tester,
      'dashboard_data_ar_light_320x568_x2',
      _v('ar', Brightness.light, const Size(320, 568), scale: 2),
      connections: {
        ServiceKind.sonarr: sonarr,
        ServiceKind.qbittorrent: torrent,
      },
      sources: {
        ServiceKind.sonarr: healthy(),
        ServiceKind.qbittorrent: healthy(),
      },
    );
  });
}
