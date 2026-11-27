// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/presentation/detail/series_detail_screen.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'detail_harness.dart';
import 'fakes.dart';

HarnessVariant _variant({
  Locale locale = const Locale('en'),
  double scale = 1,
  Size size = const Size(360, 800),
}) => HarnessVariant(
  size: size,
  textScale: scale,
  locale: locale,
  brightness: Brightness.dark,
);

Future<void> reveal(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

Future<void> pump(
  WidgetTester tester,
  ScriptedSonarrApi api, {
  HarnessVariant? variant,
  FakeLauncher? launcher,
}) async {
  final v = variant ?? _variant();
  applyVariantView(tester, v);
  await tester.pumpWidget(detailApp(v, api: api, launcher: launcher));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('external links open only through the launcher, on tap', (
    tester,
  ) async {
    final launcher = FakeLauncher();
    await pump(tester, detailApi(), launcher: launcher);
    expect(launcher.opened, isEmpty);
    await reveal(tester, find.text('IMDb'));
    await tester.tap(find.text('IMDb'));
    await tester.pumpAndSettle();
    expect(launcher.opened.single.scheme, 'https');
    expect(launcher.opened.single.host, 'www.imdb.com');
  });

  testWidgets('a link that cannot be opened says so', (tester) async {
    final launcher = FakeLauncher()..result = false;
    await pump(tester, detailApi(), launcher: launcher);
    await reveal(tester, find.text('IMDb'));
    await tester.tap(find.text('IMDb'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open the link"), findsOneWidget);
  });

  group('edit sheet', () {
    testWidgets('saves monitored, profile and tags', (tester) async {
      final api = detailApi()..updateResult = Result.ok(fakeDetail(1));
      await pump(tester, api);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any'));
      await tester.tap(find.text('kids'));
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final sent = api.sent.whereType<Map<String, Object?>>().last;
      expect(sent['qualityProfileId'], 2);
      expect(sent['tags'], [5]);
      expect(sent['monitored'], isFalse);
      // The sheet closes on success.
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('creates a tag inline and selects it', (tester) async {
      final api = detailApi()
        ..updateResult = Result.ok(fakeDetail(1))
        ..createTagResult = const Result.ok(ArrTag(id: 9, label: 'fresh'));
      await pump(tester, api);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'fresh');
      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();
      expect(api.sent, contains('fresh'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final sent = api.sent.whereType<Map<String, Object?>>().last;
      expect(sent['tags'], [9]);
    });

    testWidgets('failure keeps the sheet and retry works', (tester) async {
      final api = detailApi()
        ..updateResult = const Result.err(AppError(ErrorCategory.serverError));
      await pump(tester, api);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't save your changes"), findsOneWidget);
      api.updateResult = Result.ok(fakeDetail(1));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
      expect(api.count('updateSeries'), 2);
    });

    testWidgets('profiles failing to load offer a retry', (tester) async {
      final api = detailApi()
        ..profilesResult = const Result.err(AppError(ErrorCategory.timeout));
      await pump(tester, api);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load profiles and tags"), findsOneWidget);
    });

    for (final v in [
      _variant(
        size: const Size(320, 568),
        scale: 2,
        locale: const Locale('ar'),
      ),
      _variant(
        size: const Size(320, 568),
        scale: 2,
        locale: const Locale('en', 'XA'),
      ),
    ]) {
      testWidgets('is accessible at ${v.label}', (tester) async {
        await pump(tester, detailApi(), variant: v);
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        expectNoFrameworkExceptions(tester, context: v.label);
        await expectAccessible(tester);
      });
    }
  });

  group('search', () {
    Finder seasonMenu(int n) => find.descendant(
      of: find.byKey(ValueKey('season-$n')),
      matching: find.byIcon(Icons.more_vert),
    );

    testWidgets('season search asks first and states the load', (tester) async {
      final api = detailApi();
      await pump(tester, api);
      await reveal(tester, find.byKey(const ValueKey('season-2')));
      await tester.tap(seasonMenu(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search this season'));
      await tester.pumpAndSettle();
      expect(find.textContaining('load on your indexers'), findsOneWidget);
      expect(api.count('startCommand'), 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.count('startCommand'), 0);

      await tester.tap(seasonMenu(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search this season'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      final request = api.sent.whereType<ArrCommandRequest>().single;
      expect(request.name, 'SeasonSearch');
      expect(request.params['seasonNumber'], 2);
      // Finished without anything in the queue: said inline.
      expect(find.text('Nothing found'), findsWidgets);
    });

    testWidgets('search all missing is confirmed and runs once', (
      tester,
    ) async {
      final api = detailApi();
      await pump(tester, api);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search all missing episodes'));
      await tester.pumpAndSettle();
      expect(find.text('Search all missing episodes?'), findsOneWidget);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(
        api.sent.whereType<ArrCommandRequest>().single.name,
        'SeriesSearch',
      );
    });

    testWidgets('episode search shows progress and the result inline', (
      tester,
    ) async {
      final api = detailApi()
        ..queueResult = Result.ok([fakeQueueItem(3, seriesId: 1)]);
      await pump(tester, api);
      await reveal(tester, find.byTooltip('Search for this episode'));
      await tester.ensureVisible(
        find.byTooltip('Search for this episode').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search for this episode').first);
      await tester.pumpAndSettle();
      expect(
        api.sent.whereType<ArrCommandRequest>().single.name,
        'EpisodeSearch',
      );
    });
  });

  testWidgets('a failed episode toggle shows a row error with retry', (
    tester,
  ) async {
    final api = detailApi()
      ..monitorResult = const Result.err(AppError(ErrorCategory.timeout));
    await pump(tester, api);
    final row = find.byKey(const ValueKey('episode-4'));
    await reveal(tester, row);
    final toggle = find.descendant(of: row, matching: find.byType(Switch));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save the change"), findsOneWidget);
    api.monitorResult = const Result.ok(null);
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Try again')),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save the change"), findsNothing);
  });

  group('provider transition (server switch)', () {
    testWidgets('shows loading then the new server, never the old series', (
      tester,
    ) async {
      final a = detailApi();
      final b = detailApi();
      final gate = Completer<void>();
      b.hook = (name) => name == 'seriesDetail' ? gate.future : Future.value();
      b.detailResult = Result.ok(
        SonarrSeriesDetail.fromJson({
          'id': 1,
          'title': 'Other Server Show',
          'monitored': true,
        }),
      );
      final v = _variant();
      applyVariantView(tester, v);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 5, 1)),
            sonarrSessionProvider.overrideWith((ref) async {
              final n = ref.watch(_serverIndex);
              return SonarrSession(
                api: n == 0 ? a : b,
                serverId: 'srv$n',
                cache: MemoryPayloadCache(),
                clock: () => DateTime.utc(2026, 5, 1),
              );
            }),
            detailArtworkProvider.overrideWithValue(null),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return harnessApp(
                v,
                ConsolarrEffectsScope(
                  reduceMotion: true,
                  child: const SeriesDetailScreen(seriesId: 1),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);

      container.read(_serverIndex.notifier).value = 1;
      await tester.pump();
      await tester.pump();
      expect(find.text('Example Show 1'), findsNothing);
      expect(find.byType(DetailSkeleton), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Other Server Show'), findsOneWidget);
      expect(find.text('Example Show 1'), findsNothing);
    });

    testWidgets('a failing new server shows the error, not the old series', (
      tester,
    ) async {
      final a = detailApi();
      final b = ScriptedSonarrApi()
        ..detailResult = const Result.err(AppError(ErrorCategory.authFailed));
      final v = _variant();
      applyVariantView(tester, v);
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 5, 1)),
            sonarrSessionProvider.overrideWith((ref) async {
              final n = ref.watch(_serverIndex);
              return SonarrSession(
                api: n == 0 ? a : b,
                serverId: 'srv$n',
                cache: MemoryPayloadCache(),
                clock: () => DateTime.utc(2026, 5, 1),
              );
            }),
            detailArtworkProvider.overrideWithValue(null),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return harnessApp(
                v,
                const ConsolarrEffectsScope(
                  reduceMotion: true,
                  child: SeriesDetailScreen(seriesId: 1),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      container.read(_serverIndex.notifier).value = 1;
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}

class _ServerIndex extends Notifier<int> {
  @override
  int build() => 0;
  set value(int v) => state = v;
}

final _serverIndex = NotifierProvider<_ServerIndex, int>(_ServerIndex.new);
