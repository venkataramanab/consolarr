// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/calendar_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_body.dart';
import 'package:consolarr/features/sonarr/presentation/calendar/calendar_tab.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'support.dart';
import 'tab_harness.dart';

SonarrSeries _series(int id) => fakeSeries(id);

SonarrEpisode _ep(
  int id, {
  int day = 3,
  int season = 1,
  int? number,
  bool monitored = true,
  bool hasFile = false,
  String? finale,
  int hour = 12,
}) => SonarrEpisode(
  id: id,
  seriesId: id,
  seasonNumber: season,
  episodeNumber: number ?? 2,
  title: 'Example Episode $id',
  airDateUtc: DateTime.utc(2026, 5, day, hour),
  monitored: monitored,
  hasFile: hasFile,
  finaleType: finale,
  series: _series(id),
);

Widget _calendar(
  HarnessVariant v,
  ScriptedSonarrApi api, {
  MemoryPayloadCache? cache,
}) => tabApp(
  v,
  api: api,
  cache: cache,
  body: (context, padding) => CalendarBody(padding: padding),
);

void main() {
  testWidgets('range list: day groups, tags, status, today header', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..calendarResult = Result.ok([
        _ep(1, day: 1),
        _ep(2, number: 1),
        _ep(3, day: 5, finale: 'season'),
        _ep(4, day: 6, hasFile: true),
        _ep(5, day: 7, monitored: false),
      ]);
    await pumpMatrix(
      tester,
      (v) => _calendar(v, api),
      variants: [plainVariant],
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text('Example Show 1'), findsOneWidget);
    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.textContaining(l10n.sonarrCalendarTagPremiere), findsOneWidget);
    expect(find.textContaining(l10n.sonarrCalendarTagFinale), findsOneWidget);
    expect(
      find.textContaining(l10n.sonarrCalendarStatusDownloaded),
      findsOneWidget,
    );
    expect(find.textContaining('S1E2'), findsWidgets);
    expect(
      find.textContaining(l10n.sonarrCalendarUnmonitoredTag),
      findsOneWidget,
    );
    // First call: default range of 14 days from today, monitored only.
    final (start, end, unmonitored) =
        api.sent.first as (DateTime, DateTime, bool);
    expect(end.difference(start).inDays, calendarRangeDays);
    expect(unmonitored, isFalse);
  });

  testWidgets('empty range shows the empty state', (tester) async {
    final api = ScriptedSonarrApi();
    await pumpMatrix(tester, (v) => _calendar(v, api), variants: tabWorst);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.sonarrCalendarEmptyRangeHeadline), findsNothing);
    await pumpMatrix(
      tester,
      (v) => _calendar(v, api),
      variants: [plainVariant],
    );
    expect(find.text(l10n.sonarrCalendarEmptyRangeHeadline), findsOneWidget);
  });

  testWidgets('loading skeleton while the server answers', (tester) async {
    final gate = Completer<void>();
    final api = ScriptedSonarrApi()..hook = (_) => gate.future;
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_calendar(plainVariant, api));
    await tester.pump();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.bySemanticsLabel(l10n.sonarrCalendarLoading), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(l10n.sonarrCalendarLoading), findsNothing);
  });

  for (final category in [
    ErrorCategory.authFailed,
    ErrorCategory.networkUnreachable,
    ErrorCategory.unsupportedVersion,
    ErrorCategory.tlsPinMismatch,
  ]) {
    testWidgets('error ${category.code} with retry', (tester) async {
      final api = ScriptedSonarrApi()
        ..calendarResult = Result.err(AppError(category));
      await pumpMatrix(
        tester,
        (v) => _calendar(v, api),
        variants: [plainVariant],
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.sonarrCalendarErrorTitle), findsOneWidget);
      expect(find.text(l10n.sonarrRetry), findsOneWidget);
      // Error states show no cached data.
      expect(find.text('Example Show 1'), findsNothing);
      api.calendarResult = Result.ok([_ep(1, day: 2)]);
      await tester.tap(find.text(l10n.sonarrRetry));
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
    });
  }

  testWidgets('offline: cached window under an age banner', (tester) async {
    final cache = MemoryPayloadCache();
    final api = ScriptedSonarrApi()
      ..calendarResult = Result.ok([_ep(1, day: 2)]);
    await pumpMatrix(
      tester,
      (v) => _calendar(v, api, cache: cache),
      variants: [plainVariant],
    );
    // Same cache, server down.
    api.calendarResult = const Result.err(
      AppError(ErrorCategory.networkUnreachable),
    );
    await pumpMatrix(
      tester,
      (v) => tabApp(
        v,
        api: api,
        cache: cache,
        now: DateTime.utc(2026, 5, 1, 15),
        body: (context, padding) => CalendarBody(padding: padding),
      ),
      variants: tabStress,
      verify: (v) async {
        final l10n = lookupAppLocalizations(v.locale);
        expect(find.text(l10n.sonarrOfflineMessage), findsOneWidget);
        // Below the banner on the smallest, largest-text variants: lazy.
        if (v.size.height > 600) {
          expect(find.textContaining('Example Show 1'), findsOneWidget);
        }
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('stress variants are accessible and do not overflow', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..calendarResult = Result.ok([
        for (var i = 1; i <= 6; i++)
          SonarrEpisode(
            id: i,
            seriesId: i,
            seasonNumber: 1,
            episodeNumber: 1,
            title: 'Example Episode ${'Very Long Title ' * 8}',
            airDateUtc: DateTime.utc(2026, 5, 1 + i, 12),
            series: fakeSeries(i, title: 'Example Show ${'Long ' * 12}$i'),
            finaleType: i.isEven ? 'season' : null,
          ),
      ]);
    await pumpMatrix(
      tester,
      (v) => _calendar(v, api),
      variants: tabStress,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('10,000 episodes stay lazy', (tester) async {
    final api = ScriptedSonarrApi()
      ..calendarResult = Result.ok([
        for (var i = 1; i <= 10000; i++) _ep(i, day: 2 + i % 12),
      ]);
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_calendar(plainVariant, api));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Only a screenful of rows is built.
    expect(find.textContaining('Example Show'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Example Show').evaluate().length, lessThan(40));
  });

  group('window and toggles', () {
    testWidgets('earlier/later move the range; unmonitored re-queries', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..calendarResult = Result.ok([_ep(1, day: 2)]);
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(
        tabApp(
          plainVariant,
          api: api,
          body: (context, padding) => Column(
            children: [
              const CalendarActions(),
              Expanded(child: CalendarBody(padding: padding)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.sonarrCalendarLater));
      await tester.pumpAndSettle();
      final later = api.sent.last as (DateTime, DateTime, bool);
      expect(later.$1, DateTime(2026, 5, 15));
      await tester.tap(find.byTooltip(l10n.sonarrCalendarToday));
      await tester.pumpAndSettle();
      expect(
        (api.sent.last as (DateTime, DateTime, bool)).$1,
        DateTime(2026, 5),
      );
      await tester.tap(find.byTooltip(l10n.sonarrCalendarShowUnmonitored));
      await tester.pumpAndSettle();
      expect((api.sent.last as (DateTime, DateTime, bool)).$3, isTrue);
      expect(
        find.byTooltip(l10n.sonarrCalendarHideUnmonitored),
        findsOneWidget,
      );
    });

    testWidgets('month view: counts, selecting a day, empty day', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..calendarResult = Result.ok([_ep(1, day: 3), _ep(2, day: 3)]);
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(
        tabApp(
          plainVariant,
          api: api,
          body: (context, padding) => Column(
            children: [
              const CalendarActions(),
              Expanded(child: CalendarBody(padding: padding)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.byTooltip(l10n.sonarrCalendarShowMonth));
      await tester.pumpAndSettle();
      final window = api.sent.last as (DateTime, DateTime, bool);
      expect(window.$1, DateTime(2026, 5));
      expect(window.$2, DateTime(2026, 6));
      expect(find.text(l10n.sonarrCalendarPickDay), findsOneWidget);
      // Day 3 has two episodes, announced in its label.
      final day3 = find.bySemanticsLabel(RegExp('May 3.*2 episodes'));
      expect(day3, findsOneWidget);
      await tester.tap(day3);
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
      expect(find.text('Example Show 2'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('May 4,')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.sonarrCalendarEmptyDay), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.sonarrCalendarNextMonth));
      await tester.pumpAndSettle();
      expect(
        (api.sent.last as (DateTime, DateTime, bool)).$1,
        DateTime(2026, 6),
      );
    });

    testWidgets('month view survives 320x568, scale 2.0, ar and en_XA', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..calendarResult = Result.ok([_ep(1, day: 3)]);
      await pumpMatrix(
        tester,
        (v) => ProviderScope(
          overrides: [
            ...sonarrTestOverrides(api),
            calendarViewProvider.overrideWith(_MonthView.new),
            artworkSourceProvider.overrideWithValue(null),
          ],
          child: harnessApp(
            v,
            Scaffold(
              body: Builder(
                builder: (context) => calendarTab.body(
                  context,
                  const EdgeInsets.fromLTRB(16, 72, 16, 88),
                ),
              ),
            ),
          ),
        ),
        variants: tabStress,
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  testWidgets('tapping an episode opens its series', (tester) async {
    final api = ScriptedSonarrApi()
      ..calendarResult = Result.ok([_ep(7, day: 2)]);
    String? opened;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: calendarTab.body(
              context,
              const EdgeInsets.fromLTRB(16, 72, 16, 88),
            ),
          ),
        ),
        GoRoute(
          path: '/sonarr/series/:id',
          builder: (context, state) {
            opened = state.pathParameters['id'];
            return const Scaffold();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...sonarrTestOverrides(api),
          artworkSourceProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sonarrSeriesLocation(7), '/sonarr/series/7');
    await tester.tap(find.text('Example Show 7'));
    await tester.pumpAndSettle();
    expect(opened, '7');
  });

  group('provider transitions', () {
    testWidgets('a server switch shows the skeleton, then the new server; an '
        'error never shows the previous server data', (tester) async {
      final apiA = ScriptedSonarrApi()
        ..calendarResult = Result.ok([_ep(1, day: 2)]);
      // Server B rejects the credentials (after the gate opens).
      final apiB = ScriptedSonarrApi()
        ..calendarResult = const Result.err(
          AppError(ErrorCategory.authFailed),
        );
      final gate = Completer<void>();
      apiB.hook = (_) => gate.future;
      final apis = [apiA, apiB];
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            _selected.overrideWith(_Selected.new),
            artworkSourceProvider.overrideWithValue(null),
            sonarrSessionProvider.overrideWith(
              (ref) => SonarrSession(
                api: apis[ref.watch(_selected)],
                serverId: 'srv${ref.watch(_selected)}',
                cache: MemoryPayloadCache(),
                clock: () => DateTime.utc(2026, 5, 1, 12),
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 5, 1, 12)),
          ],
          child: harnessApp(
            plainVariant,
            Scaffold(
              body: Builder(
                builder: (context) => calendarTab.body(
                  context,
                  const EdgeInsets.fromLTRB(16, 72, 16, 88),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      container.read(_selected.notifier).pick(1);
      await tester.pump();
      await tester.pump();
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text('Example Show 1'), findsNothing);
      expect(find.bySemanticsLabel(l10n.sonarrCalendarLoading), findsOneWidget);
      apiB.calendarResult = const Result.err(
        AppError(ErrorCategory.authFailed),
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsNothing);
      expect(find.text(l10n.sonarrCalendarErrorTitle), findsOneWidget);
    });
  });
}

class _MonthView extends CalendarViewNotifier {
  @override
  CalendarView build() => CalendarView(
    mode: CalendarMode.month,
    anchor: DateTime(2026, 5, 1),
    includeUnmonitored: false,
    selectedDay: DateTime(2026, 5, 3),
  );
}

final _selected = NotifierProvider<_Selected, int>(_Selected.new);

class _Selected extends Notifier<int> {
  @override
  int build() => 0;

  void pick(int i) => state = i;
}
