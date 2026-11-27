// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/library_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:consolarr/features/sonarr/presentation/home/sonarr_home_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'support.dart';

/// A library notifier that serves a fixed state; `null` stays loading.
class FakeLibraryNotifier extends SeriesLibraryNotifier {
  FakeLibraryNotifier(this.initial, {this.onRefresh});

  final LibraryState? initial;
  final Future<void> Function()? onRefresh;
  int refreshCalls = 0;

  @override
  Future<LibraryState> build() {
    final state = initial;
    return state == null
        ? Completer<LibraryState>().future
        : Future.value(state);
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
    await onRefresh?.call();
  }
}

class MemoryViewModeStore implements ViewModeStore {
  MemoryViewModeStore([this.stored]);
  LibraryViewMode? stored;
  @override
  Future<LibraryViewMode?> read() async => stored;
  @override
  Future<void> write(LibraryViewMode mode) async => stored = mode;
}

/// An artwork source that counts how often each poster is requested.
class CountingArtworkSource extends ArtworkSource {
  CountingArtworkSource() : super(dio: Dio(), api: FakeSonarrApi());

  final Map<int, int> requests = {};

  @override
  ImageProvider? poster(SonarrSeries series) {
    requests.update(series.id, (n) => n + 1, ifAbsent: () => 1);
    return null;
  }
}

final fixedNow = DateTime(2026, 5, 1, 12);

LibraryData dataState(
  List<SonarrSeries> list, {
  AppError? offlineError,
  Duration age = Duration.zero,
}) => LibraryData(
  SeriesSnapshot(
    series: list,
    fetchedAt: fixedNow.subtract(age),
    offlineError: offlineError,
  ),
);

/// The library screen inside the harness app, with providers faked.
///
/// Motion is reduced so skeletons settle; pass [reduceMotion] false to test
/// the shimmer itself.
Widget libraryApp(
  HarnessVariant variant, {
  required FakeLibraryNotifier notifier,
  ArtworkSource? artwork,
  LibraryViewMode mode = LibraryViewMode.grid,
  bool reduceMotion = true,
  VoidCallback? onOpenServers,
  ScriptedSonarrApi? api,
  SonarrPrefsStore? prefs,
  RouteRecorder? recorder,
}) {
  return ProviderScope(
    overrides: [
      ...sonarrTestOverrides(
        api ?? ScriptedSonarrApi(),
        prefs: prefs,
        now: fixedNow,
      ),
      libraryRunnerProvider.overrideWithValue(inlineRunner),
      seriesLibraryProvider.overrideWith(() => notifier),
      artworkSourceProvider.overrideWithValue(artwork),
      viewModeStoreProvider.overrideWithValue(MemoryViewModeStore(mode)),
    ],
    child: harnessApp(
      variant,
      _routed(
        recorder,
        ConsolarrEffectsScope(
          reduceMotion: reduceMotion,
          child: Builder(
            builder: (context) {
              // The shell raises the bottom padding by the floating nav bar.
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(bottom: 88),
                ),
                child: Scaffold(
                  body: SonarrHomeScreen(onOpenServers: onOpenServers),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Runs library queries inline (no isolate) so tests stay deterministic.
Future<T> inlineRunner<T>(T Function() computation) async => computation();

/// Remembers where the screen navigated.
class RouteRecorder {
  /// Location of the most recently built non-home route, or empty.
  String location = '';
}

Widget _routed(RouteRecorder? recorder, Widget home) {
  if (recorder == null) return home;
  Widget visit(GoRouterState state) {
    recorder.location = state.uri.toString();
    return const Scaffold();
  }

  return Router.withConfig(
    config: GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => home),
        GoRoute(path: '/sonarr/add', builder: (context, state) => visit(state)),
        GoRoute(
          path: '/sonarr/series/:id',
          builder: (context, state) => visit(state),
        ),
      ],
    ),
  );
}
