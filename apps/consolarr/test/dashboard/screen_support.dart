// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_screen.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

class SeededConnections extends ActiveConnections {
  SeededConnections(this.initial);

  final Map<ServiceKind, Object?> initial;

  @override
  Map<ServiceKind, Object?> build() => initial;
}

const kLink = DashboardLink(
  '/sonarr',
  DashboardTarget.tab,
  DashboardDestination.sonarr,
);

ActivitySummary summary({
  int active = 2,
  int attention = 0,
  List<ActivityRow>? rows,
  int? down,
  int? up,
  bool speedUnavailable = false,
}) => ActivitySummary(
  active: active,
  attention: attention,
  link: kLink,
  downSpeed: down,
  upSpeed: up,
  speedUnavailable: speedUnavailable,
  rows:
      rows ??
      const [
        ActivityRow(
          id: 'q:1',
          title: 'Example Show',
          state: ActivityState.downloading,
          progress: 0.42,
          sizeLeft: 734003200,
          eta: Duration(minutes: 12),
        ),
        ActivityRow(
          id: 'q:2',
          title: 'Another Example Show',
          state: ActivityState.attention,
          progress: 0.9,
        ),
      ],
);

/// A dashboard under [variant] with every kind's active server given by
/// [connections] (a connection, `null`, an [AppError] or a pending
/// [Completer]).
Widget dashboardApp(
  HarnessVariant variant,
  Env env, {
  required Map<ServiceKind, Object?> connections,
  required Map<ServiceKind, DashboardSource> sources,
  bool noServers = false,
  bool reduceMotion = true,
  Override? appLocked,
  Widget Function(Widget screen)? wrapScreen,
  List<Override> extra = const [],
}) {
  final entries = noServers
      ? <ServerEntry>[]
      : [
          for (final e in connections.entries)
            if (e.value is ServerConnection)
              ServerEntry(
                profile: (e.value! as ServerConnection).profile,
                sortOrder: 0,
              ),
        ];
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ...env.overrides(sources: sources),
      activeConnections.overrideWith(() => SeededConnections(connections)),
      uiServersProvider.overrideWithValue(
        AsyncData(
          entries.isEmpty && !noServers
              ? [
                  ServerEntry(
                    profile: ServerProfile.parse(
                      id: 'p',
                      name: 'Placeholder',
                      kind: ServiceKind.sonarr,
                      address: 'https://p.example',
                    ).valueOrNull!,
                    sortOrder: 0,
                  ),
                ]
              : entries,
        ),
      ),
      appLocked ?? appLockedProvider.overrideWithValue(false),
      ...extra,
    ],
    child: harnessApp(
      variant,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: wrapScreen == null
              ? const Scaffold(body: DashboardScreen())
              : wrapScreen(const Scaffold(body: DashboardScreen())),
        ),
      ),
    ),
  );
}

/// The variants of the brief: 320x568 and 412x915, en / en_XA / ar, text
/// scale 1.0 and 2.0, dark and light.
List<HarnessVariant> briefMatrix() =>
    harnessMatrix(sizes: const [Size(320, 568), Size(412, 915)]);
