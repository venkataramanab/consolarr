// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/application/wanted_providers.dart';
import 'package:consolarr/features/sonarr/data/wanted_repository.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_body.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'support.dart';
import 'tab_harness.dart';

SonarrEpisode _missing(int id, {int seriesId = 1, int day = 20}) =>
    SonarrEpisode(
      id: id,
      seriesId: seriesId,
      seasonNumber: 1,
      episodeNumber: id,
      title: 'Example Episode $id',
      airDateUtc: DateTime.utc(2026, 4, day, 12),
      monitored: true,
      series: fakeSeries(seriesId),
    );

ArrPage<SonarrEpisode> _page(
  List<SonarrEpisode> eps, {
  int page = 1,
  int total = -1,
}) => ArrPage(
  records: eps,
  page: page,
  pageSize: 50,
  totalRecords: total < 0 ? eps.length : total,
);

final _l10n = lookupAppLocalizations(const Locale('en'));

Widget _wanted(
  HarnessVariant v,
  ScriptedSonarrApi api, {
  ManualSearchOpener? onManualSearch,
}) => tabApp(
  v,
  api: api,
  body: (context, padding) => WantedBody(
    padding: padding,
    onManualSearch: onManualSearch ?? (context, episode, title) {},
  ),
);

void main() {
  group('repository', () {
    test('wanted merges missing and cutoff-unmet without duplicates', () async {
      final api = ScriptedSonarrApi()
        ..wantedResult = Result.ok(_page([_missing(1), _missing(2)]));
      final repo = WantedRepository(api: api, clock: DateTime.now);
      final page = (await repo.load(WantedScope.wanted)).valueOrNull!;
      // Same fake answers both lists: duplicates collapse.
      expect(page.episodes.map((e) => e.id), [1, 2]);
      expect(api.count('wanted'), 2);
    });

    test('a failing cutoff list does not hide the missing list', () async {
      final api = _CutoffFailsApi()
        ..wantedResult = Result.ok(_page([_missing(1)]));
      final repo = WantedRepository(api: api, clock: DateTime.now);
      expect(
        (await repo.load(WantedScope.wanted)).valueOrNull!.episodes,
        hasLength(1),
      );
    });

    test('missing errors are returned', () async {
      final api = ScriptedSonarrApi()
        ..wantedResult = const Result.err(AppError(ErrorCategory.authFailed));
      final repo = WantedRepository(api: api, clock: DateTime.now);
      expect(
        (await repo.load(WantedScope.missing)).errorOrNull?.category,
        ErrorCategory.authFailed,
      );
    });

    test('upcoming reads the next 14 days of the calendar', () async {
      final api = ScriptedSonarrApi()
        ..calendarResult = Result.ok([_missing(1)]);
      final repo = WantedRepository(
        api: api,
        clock: () => DateTime.utc(2026, 5, 1, 9),
      );
      final page = (await repo.load(WantedScope.upcoming)).valueOrNull!;
      expect(page.hasMore, isFalse);
      final (start, end, _) = api.sent.single as (DateTime, DateTime, bool);
      expect(end.difference(start).inDays, 14);
      expect(start, DateTime.utc(2026, 5));
    });
  });

  testWidgets('groups by series; expanding shows episodes with search', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(
        _page([_missing(1), _missing(2), _missing(3, seriesId: 2)]),
      );
    SonarrEpisode? manual;
    await pumpMatrix(
      tester,
      (v) => _wanted(v, api, onManualSearch: (c, e, t) => manual = e),
      variants: [plainVariant],
    );
    expect(find.text('Example Show 1'), findsOneWidget);
    expect(find.text('Example Show 2'), findsOneWidget);
    expect(find.textContaining('S1E1'), findsNothing);
    await tester.tap(find.text('Example Show 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('S1E1'), findsOneWidget);
    expect(find.byTooltip(_l10n.sonarrSearchEpisode), findsNWidgets(2));
    await tester.tap(find.byTooltip(_l10n.sonarrWantedManualSearch).first);
    expect(manual?.id, 1);
  });

  testWidgets('per-episode automatic search runs inline', (tester) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(_page([_missing(1)]))
      ..queueResult = Result.ok([fakeQueueItem(1)]);
    await pumpMatrix(tester, (v) => _wanted(v, api), variants: [plainVariant]);
    await tester.tap(find.text('Example Show 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(_l10n.sonarrSearchEpisode));
    await tester.pumpAndSettle();
    expect(api.count('startCommand'), 1);
    expect(find.text(_l10n.sonarrSearchGrabbed), findsOneWidget);
  });

  testWidgets('empty-good, upcoming-empty and filter-empty states', (
    tester,
  ) async {
    final api = ScriptedSonarrApi();
    await pumpMatrix(
      tester,
      (v) => _wanted(v, api),
      variants: tabStress,
      verify: (v) async {
        expect(
          find.text(
            lookupAppLocalizations(v.locale).sonarrWantedEmptyGoodHeadline,
          ),
          findsOneWidget,
        );
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('upcoming scope has its own empty state and no search-all', (
    tester,
  ) async {
    final api = ScriptedSonarrApi();
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sonarrWantedSearchAll), findsOneWidget);
    await tester.tap(find.text(_l10n.sonarrWantedScopeUpcoming));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sonarrWantedEmptyUpcomingHeadline), findsOneWidget);
    expect(find.text(_l10n.sonarrWantedSearchAll), findsNothing);
  });

  testWidgets('filter-empty offers to clear the filter', (tester) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(_page([_missing(1)]));
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(_l10n.sonarrWantedFilterEmptyHeadline), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, _l10n.sonarrWantedFilterClear),
    );
    await tester.pumpAndSettle();
    expect(find.text('Example Show 1'), findsOneWidget);
    // A matching filter keeps the series.
    await tester.enterText(find.byType(TextField), 'show 1');
    await tester.pumpAndSettle();
    expect(find.text('Example Show 1'), findsOneWidget);
  });

  testWidgets('loading skeleton, then data', (tester) async {
    final gate = Completer<void>();
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(_page([_missing(1)]))
      ..hook = (_) => gate.future;
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pump();
    expect(find.bySemanticsLabel(_l10n.sonarrWantedLoading), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Example Show 1'), findsOneWidget);
  });

  for (final category in [
    ErrorCategory.authFailed,
    ErrorCategory.networkUnreachable,
    ErrorCategory.serverError,
  ]) {
    testWidgets('error ${category.code}: scope stays usable, retry works', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..wantedResult = Result.err(AppError(category));
      await pumpMatrix(
        tester,
        (v) => _wanted(v, api),
        variants: tabWorst,
        verify: (v) => expectAccessible(tester),
      );
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(_wanted(plainVariant, api));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.sonarrWantedErrorTitle), findsOneWidget);
      api.wantedResult = Result.ok(_page([_missing(1)]));
      await tester.tap(find.text(_l10n.sonarrRetry));
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
    });
  }

  testWidgets('offline refresh keeps the list, disables writes with a reason', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(_page([_missing(1)]));
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Show 1'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(_l10n.sonarrSearchEpisode), findsOneWidget);
    api.wantedResult = const Result.err(
      AppError(ErrorCategory.networkUnreachable),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WantedBody)),
    );
    await container.read(wantedProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(
      find.textContaining(_l10n.sonarrWantedOfflineWrites),
      findsOneWidget,
    );
    expect(find.byTooltip(_l10n.sonarrSearchEpisode), findsNothing);
    expect(find.byTooltip(_l10n.sonarrWantedManualSearch), findsNothing);
    final searchAll = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(_l10n.sonarrWantedSearchAll),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(searchAll.onPressed, isNull);
    // Auth errors are never shown as stale data.
    api.wantedResult = const Result.err(AppError(ErrorCategory.authFailed));
    await container.read(wantedProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('Example Show 1'), findsNothing);
  });

  group('search all missing', () {
    testWidgets('asks first, states the consequence; cancel sends nothing', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..wantedResult = Result.ok(_page([_missing(1)]));
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(_wanted(plainVariant, api));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.sonarrWantedSearchAll));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.sonarrWantedSearchAllBody), findsOneWidget);
      await tester.tap(find.text(_l10n.sonarrWantedCancel));
      await tester.pumpAndSettle();
      expect(api.count('startCommand'), 0);
    });

    testWidgets('confirm starts one MissingEpisodeSearch and reports done', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..wantedResult = Result.ok(_page([_missing(1)]));
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(_wanted(plainVariant, api));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.sonarrWantedSearchAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.sonarrWantedSearchAllConfirm));
      await tester.pumpAndSettle();
      expect(api.count('startCommand'), 1);
      expect(
        (api.sent.whereType<ArrCommandRequest>().single).name,
        'MissingEpisodeSearch',
      );
      expect(find.text(_l10n.sonarrWantedSearchAllDone), findsOneWidget);
    });

    testWidgets('failure offers a retry', (tester) async {
      final api = ScriptedSonarrApi()
        ..wantedResult = Result.ok(_page([_missing(1)]))
        ..startResult = const Result.err(AppError(ErrorCategory.serverError));
      applyVariantView(tester, plainVariant);
      await tester.pumpWidget(_wanted(plainVariant, api));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.sonarrWantedSearchAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.sonarrWantedSearchAllConfirm));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.sonarrWantedSearchAllFailed), findsOneWidget);
      expect(find.text(_l10n.sonarrWantedSearchAllRetry), findsOneWidget);
    });
  });

  testWidgets('load more appends the next page', (tester) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(_page([_missing(1)], total: 100));
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pumpAndSettle();
    api.wantedResult = Result.ok(
      _page([_missing(2, seriesId: 2)], page: 2, total: 100),
    );
    await tester.scrollUntilVisible(
      find.text(_l10n.sonarrWantedLoadMore),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(_l10n.sonarrWantedLoadMore));
    await tester.pumpAndSettle();
    expect(find.text('Example Show 2'), findsOneWidget);
  });

  testWidgets('10,000 episodes in many series stay lazy', (tester) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(
        _page([for (var i = 1; i <= 10000; i++) _missing(i, seriesId: i)]),
      );
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Example Show').evaluate().length, lessThan(40));
  });

  testWidgets('one series with 10,000 expanded episodes stays lazy', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(
        _page([for (var i = 1; i <= 10000; i++) _missing(i)]),
      );
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(_wanted(plainVariant, api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Show 1'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Example Episode').evaluate().length,
      lessThan(40),
    );
  });

  testWidgets('data states are accessible in every stress variant', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(
        _page([
          for (var i = 1; i <= 4; i++)
            SonarrEpisode(
              id: i,
              seriesId: i,
              seasonNumber: 1,
              episodeNumber: i,
              title: 'Example Episode ${'Very Long Title ' * 8}',
              airDateUtc: DateTime.utc(2026, 4, 20),
              series: fakeSeries(i, title: 'Example Show ${'Long ' * 12}$i'),
            ),
        ]),
      );
    await pumpMatrix(
      tester,
      (v) => _wanted(v, api),
      variants: tabStress,
      verify: (v) => expectAccessible(tester),
    );
  });

  testWidgets('switching server: skeleton then error, never old data', (
    tester,
  ) async {
    final apiA = ScriptedSonarrApi()
      ..wantedResult = Result.ok(_page([_missing(1)]));
    final apiB = ScriptedSonarrApi()
      ..wantedResult = const Result.err(AppError(ErrorCategory.authFailed));
    final gate = Completer<void>();
    apiB.hook = (_) => gate.future;
    final apis = [apiA, apiB];
    applyVariantView(tester, plainVariant);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _server.overrideWith(_Server.new),
          artworkSourceProvider.overrideWithValue(null),
          sonarrSessionProvider.overrideWith(
            (ref) => SonarrSession(
              api: apis[ref.watch(_server)],
              serverId: 'srv${ref.watch(_server)}',
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
              builder: (context) => WantedBody(
                padding: const EdgeInsets.fromLTRB(16, 72, 16, 88),
                onManualSearch: (c, e, t) {},
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
    container.read(_server.notifier).pick(1);
    await tester.pump();
    await tester.pump();
    expect(find.text('Example Show 1'), findsNothing);
    expect(find.bySemanticsLabel(_l10n.sonarrWantedLoading), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Example Show 1'), findsNothing);
    expect(find.text(_l10n.sonarrWantedErrorTitle), findsOneWidget);
  });

  test('the missing search target sends MissingEpisodeSearch', () {
    expect(const SearchTarget.missing().request.name, 'MissingEpisodeSearch');
  });
}

class _CutoffFailsApi extends ScriptedSonarrApi {
  @override
  Future<Result<ArrPage<SonarrEpisode>>> wanted(
    SonarrWantedKind kind, {
    int page = 1,
    int pageSize = 50,
  }) async => kind == SonarrWantedKind.cutoffUnmet
      ? const Result.err(AppError(ErrorCategory.notFound))
      : super.wanted(kind, page: page, pageSize: pageSize);
}

final _server = NotifierProvider<_Server, int>(_Server.new);

class _Server extends Notifier<int> {
  @override
  int build() => 0;

  void pick(int i) => state = i;
}
