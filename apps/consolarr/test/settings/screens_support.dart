// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/connection_check.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/device_authenticator.dart';
import 'package:consolarr/features/settings/settings_routes.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/router.dart';
import 'package:design_system/design_system.dart';
import 'package:consolarr/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../servers/ui/support.dart' hide RecordingAnalytics;
import 'support.dart';

export '../servers/ui/support.dart' hide RecordingAnalytics;
export 'support.dart';

const wide = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

/// The stress variants every screen must survive: 320x568, scale 2.0, in
/// Arabic and the pseudo-locale, light and dark.
final stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

class _DoneFirstFrame extends FirstFrameDone {
  @override
  bool build() => true;
}

/// A fake connection tester recording calls.
class ScriptedTester extends FakeTester {}

/// Fake probe that always succeeds.
class OkProbe implements NetworkProbe {
  const OkProbe();

  @override
  Future<bool> resolves(String host) async => true;

  @override
  Future<bool> connects(String host, int port) async => true;
}

/// Everything a settings screen test needs.
class ScreenHarness {
  ScreenHarness({
    Map<String, String>? stored,
    FakeDeviceAuthenticator? auth,
    List<ServerEntry> servers = const [],
    this.supportPending = false,
    bool recordingSinks = true,
    this.serversStream,
    this.healthTester,
    this.uiServers,
  }) : base = SettingsHarness(
         stored: stored,
         auth: auth,
         recordingSinks: recordingSinks,
       ),
       ui = UiHarness(servers: servers),
       serverList = servers;

  final SettingsHarness base;
  final UiHarness ui;
  final List<ServerEntry> serverList;
  final bool supportPending;

  /// Replaces the stream behind `serversProvider` (errors, delays).
  final Stream<List<ServerEntry>> Function()? serversStream;

  /// Replaces the tester the connection check uses.
  final ConnectionTester? healthTester;

  /// Replaces the UI server list (for example an error).
  final AsyncValue<List<ServerEntry>>? uiServers;

  List<Override> get overrides => [
    // Screens are shown after the first frame.
    firstFrameDoneProvider.overrideWith(_DoneFirstFrame.new),
    serverRepositoryProvider.overrideWithValue(ui.repo),
    connectionTesterProvider.overrideWithValue(ui.tester),
    healthTesterProvider.overrideWithValue(healthTester ?? ui.tester),
    pinStoreProvider.overrideWithValue(ui.pins),
    ...base.overrides,
    uiServersProvider.overrideWithValue(uiServers ?? AsyncData(serverList)),
    serversProvider.overrideWith(
      (ref) => serversStream?.call() ?? Stream.value(serverList),
    ),
    networkProbeProvider.overrideWithValue(const OkProbe()),
    if (supportPending)
      deviceAuthSupportProvider.overrideWith(
        (ref) => Completer<DeviceAuthSupport>().future,
      ),
  ];

  /// A screen inside the harness app, with the settings already loaded.
  Widget screen(HarnessVariant v, Widget home) => ProviderScope(
    overrides: overrides,
    child: harnessApp(
      v,
      ConsolarrEffectsScope(reduceMotion: true, child: home),
    ),
  );

  /// The real settings destination in the real router.
  Widget routed(HarnessVariant v, {String location = '/settings'}) {
    final router = buildRouter(
      initialLocation: location,
      destinations: [
        AppDestination(
          id: 'home',
          route: '/',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: (l) => l.navHome,
          builder: (context, state) => const SizedBox(),
        ),
        settingsDestination,
      ],
    );
    return ProviderScope(
      overrides: overrides,
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
}
