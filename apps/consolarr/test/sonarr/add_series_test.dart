// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/add_series.dart';
import 'package:consolarr/features/sonarr/application/lookup_search.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart' show Image;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'add_harness.dart';
import 'fakes.dart';
import 'release_harness.dart';

void main() {
  group('term handling', () {
    test('short, blank and control-character terms are rejected', () {
      expect(normalizeLookupTerm(' '), isNull);
      expect(normalizeLookupTerm('a'), isNull);
      expect(normalizeLookupTerm('ab\u0000c'), isNull);
      expect(normalizeLookupTerm('  Example   Show '), 'Example Show');
      expect(normalizeLookupTerm('tvdb:12345'), 'tvdb:12345');
      expect(normalizeLookupTerm('x' * 500)!.length, lookupMaxTermLength);
    });
  });

  group('lookup notifier', () {
    ProviderContainer containerFor(ScriptedSonarrApi api) {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: sonarrTestOverrides(api),
      );
      addTearDown(c.dispose);
      c.listen(lookupSearchProvider, (_, _) {});
      return c;
    }

    test('only the latest search counts', () async {
      final slow = Completer<void>();
      var calls = 0;
      final api = addApi(results: [fakeLookup(1)])
        ..hook = (n) =>
            n == 'lookup' && calls++ == 0 ? slow.future : Future.value();
      final c = containerFor(api);
      final notifier = c.read(lookupSearchProvider.notifier);
      final first = notifier.search('first');
      await Future<void>.delayed(Duration.zero);
      api.lookupResult = Result.ok([fakeLookup(2), fakeLookup(3)]);
      await notifier.search('second');
      slow.complete();
      await first;
      final state = c.read(lookupSearchProvider);
      expect(state, isA<LookupResults>());
      expect((state as LookupResults).results, hasLength(2));
    });

    test('results are capped and failures reported', () async {
      final api = addApi(
        results: [for (var i = 1; i <= 80; i++) fakeLookup(i)],
      );
      final c = containerFor(api);
      await c.read(lookupSearchProvider.notifier).search('example');
      expect(
        (c.read(lookupSearchProvider) as LookupResults).results,
        hasLength(lookupMaxResults),
      );
      api.lookupResult = const Result.err(AppError(ErrorCategory.timeout));
      await c.read(lookupSearchProvider.notifier).search('example');
      expect(c.read(lookupSearchProvider), isA<LookupFailed>());
      await c.read(lookupSearchProvider.notifier).search('');
      expect(c.read(lookupSearchProvider), isA<LookupIdle>());
    });
  });

  group('add notifier', () {
    const options = SonarrAddOptions(
      qualityProfileId: 4,
      rootFolderPath: '/media/anime',
      searchForMissing: true,
    );

    test(
      'success remembers the root folder and refreshes the library',
      () async {
        final api = addApi();
        final prefs = MemorySonarrPrefsStore();
        var refreshed = 0;
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            ...sonarrTestOverrides(api, prefs: prefs),
            libraryRefreshProvider.overrideWithValue(() async => refreshed++),
          ],
        );
        addTearDown(c.dispose);
        c.listen(addSeriesProvider, (_, _) {});
        await c.read(sonarrSessionProvider.future);
        await c.read(addSeriesProvider.notifier).submit(fakeLookup(1), options);
        final state = c.read(addSeriesProvider);
        expect(state, isA<AddSuccess>());
        expect((state as AddSuccess).searched, isTrue);
        expect(await prefs.read('srv1', addRootFolderPref), '/media/anime');
        expect(refreshed, 1);
        // A second submit after success is ignored.
        await c.read(addSeriesProvider.notifier).submit(fakeLookup(1), options);
        expect(api.count('addSeries'), 1);
      },
    );

    test(
      'failure keeps the form and allows a retry; one request at a time',
      () async {
        final gate = Completer<void>();
        final api = addApi()
          ..addResult = const Result.err(AppError(ErrorCategory.serverError))
          ..hook = (n) => n == 'addSeries' ? gate.future : Future.value();
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            ...sonarrTestOverrides(api),
            libraryRefreshProvider.overrideWithValue(() async {}),
          ],
        );
        addTearDown(c.dispose);
        c.listen(addSeriesProvider, (_, _) {});
        await c.read(sonarrSessionProvider.future);
        final notifier = c.read(addSeriesProvider.notifier);
        final first = notifier.submit(fakeLookup(1), options);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(addSeriesProvider), isA<AddSubmitting>());
        await notifier.submit(fakeLookup(1), options);
        gate.complete();
        await first;
        expect(api.count('addSeries'), 1);
        expect(c.read(addSeriesProvider), isA<AddFailed>());
        api.addResult = Result.ok(fakeDetail(1));
        await notifier.submit(fakeLookup(1), options);
        expect(c.read(addSeriesProvider), isA<AddSuccess>());
      },
    );
  });

  group('form data', () {
    test('remembered root folder is preselected when it still exists', () {
      const folders = [
        ArrRootFolder(id: 1, path: '/a'),
        ArrRootFolder(id: 2, path: '/b'),
      ];
      const data = AddFormData(
        profiles: [ArrQualityProfile(id: 1, name: 'p')],
        rootFolders: folders,
        tags: [],
        rememberedRootFolder: '/b',
      );
      expect(data.defaultRootFolder!.path, '/b');
      expect(
        const AddFormData(
          profiles: [],
          rootFolders: folders,
          tags: [],
          rememberedRootFolder: '/gone',
        ).defaultRootFolder!.path,
        '/a',
      );
      expect(
        const AddFormData(
          profiles: [],
          rootFolders: folders,
          tags: [],
        ).isUsable,
        isFalse,
      );
    });
  });

  group('screen states', () {
    testWidgets('idle prompt is accessible in every variant', (tester) async {
      final api = addApi();
      await pumpMatrix(
        tester,
        (v) => addApp(v, api),
        variants: releaseVariants,
        verify: (v) async {
          if (v.textScale == 2.0 && v.size.width == 320) {
            await expectLabeledTapTargets(tester);
          }
        },
      );
    });

    testWidgets('searching shows a labelled skeleton', (tester) async {
      final gate = Completer<void>();
      final api = addApi()
        ..hook = (n) => n == 'lookup' ? gate.future : Future.value();
      applyVariantView(tester, enVariant);
      await tester.pumpWidget(addApp(enVariant, api));
      await tester.enterText(find.byType(TextField), 'example');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(find.bySemanticsLabel('Searching for series'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('results mark series already in the library, no remote art', (
      tester,
    ) async {
      final api = addApi(
        results: [fakeLookup(1), fakeLookup(2, inLibrary: true)],
      );
      await pumpAdd(tester, api, term: 'example');
      expect(find.text('Example Show 1'), findsOneWidget);
      expect(find.text('In library'), findsOneWidget);
      expect(find.byType(ArtworkPlaceholder), findsNWidgets(2));
      expect(find.byType(Image), findsNothing);
      expect(api.sent, ['example']);
    });

    testWidgets('no results', (tester) async {
      await pumpAdd(tester, addApi(), term: 'nothing');
      expect(find.text('No series found'), findsOneWidget);
    });

    testWidgets('unauthorized and unreachable errors offer a retry', (
      tester,
    ) async {
      final api = addApi()
        ..lookupResult = const Result.err(AppError(ErrorCategory.authFailed));
      await pumpAdd(tester, api, term: 'example');
      expect(find.text("Couldn't search for series"), findsOneWidget);
      api.lookupResult = Result.ok([fakeLookup(1)]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
    });

    testWidgets('a pre-filled term searches after the first frame', (
      tester,
    ) async {
      final api = addApi(results: [fakeLookup(1)]);
      applyVariantView(tester, enVariant);
      await tester.pumpWidget(addApp(enVariant, api, initialTerm: 'example'));
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
    });

    testWidgets('results at the extreme: 50 rows lazily built', (tester) async {
      final api = addApi(
        results: [for (var i = 1; i <= 80; i++) fakeLookup(i)],
      );
      await pumpAdd(tester, api, term: 'example');
      expect(find.byType(MediaListTile).evaluate().length, lessThan(50));
    });
  });

  group('options sheet', () {
    Future<void> openSheet(WidgetTester tester, ScriptedSonarrApi api) async {
      await pumpAdd(tester, api, term: 'example');
      await tester.tap(find.text('Example Show 1'));
      await tester.pumpAndSettle();
    }

    testWidgets('add sends the chosen options and shows a confirmation', (
      tester,
    ) async {
      final api = addApi(results: [fakeLookup(1)]);
      final refreshes = RefreshCounter();
      applyVariantView(tester, enVariant);
      await tester.pumpWidget(addApp(enVariant, api, refreshes: refreshes));
      await tester.enterText(find.byType(TextField), 'example');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example Show 1'));
      await tester.pumpAndSettle();
      expect(find.text('Quality profile'), findsOneWidget);
      await tester.tap(find.text('Add series').last);
      await tester.pumpAndSettle();
      expect(find.text('Series added'), findsOneWidget);
      final (_, options) =
          api.sent.last as (SonarrLookupResult, SonarrAddOptions);
      expect(options.qualityProfileId, 4);
      expect(options.rootFolderPath, '/media/tv');
      expect(options.searchForMissing, isFalse);
      expect(refreshes.count, 1);
    });

    testWidgets('add and search sets the search flag', (tester) async {
      final api = addApi(results: [fakeLookup(1)]);
      await openSheet(tester, api);
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pumpAndSettle();
      final (_, options) =
          api.sent.last as (SonarrLookupResult, SonarrAddOptions);
      expect(options.searchForMissing, isTrue);
      expect(
        find.text(
          "It's in your library and Sonarr is searching for missing episodes.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a remembered root folder is preselected', (tester) async {
      final api = addApi(results: [fakeLookup(1)]);
      final prefs = MemorySonarrPrefsStore();
      await prefs.write('srv1', addRootFolderPref, '/media/anime');
      applyVariantView(tester, enVariant);
      await tester.pumpWidget(addApp(enVariant, api, prefs: prefs));
      await tester.enterText(find.byType(TextField), 'example');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example Show 1'));
      await tester.pumpAndSettle();
      expect(find.text('/media/anime'), findsOneWidget);
    });

    testWidgets('failure shows the cause with retry; nothing is lost', (
      tester,
    ) async {
      final api = addApi(results: [fakeLookup(1)])
        ..addResult = const Result.err(AppError(ErrorCategory.serverError));
      await openSheet(tester, api);
      await tester.tap(find.text('Add series').last);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't add the series"), findsOneWidget);
      api.addResult = Result.ok(fakeDetail(1));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Series added'), findsOneWidget);
      expect(api.count('addSeries'), 2);
    });

    testWidgets('a tag can be created inline and is selected', (tester) async {
      final api = addApi(results: [fakeLookup(1)]);
      await openSheet(tester, api);
      final field = find.widgetWithText(TextField, 'New tag');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'new');
      await tester.tap(find.byTooltip('Create tag'));
      await tester.pumpAndSettle();
      expect(api.sent, contains('new'));
      await tester.tap(find.text('Add series').last);
      await tester.pumpAndSettle();
      final (_, options) =
          api.sent.last as (SonarrLookupResult, SonarrAddOptions);
      expect(options.tags, [99]);
    });

    testWidgets('no profile or root folder explains what to do', (
      tester,
    ) async {
      final api = addApi(results: [fakeLookup(1)], usable: false);
      await openSheet(tester, api);
      expect(find.text("Sonarr isn't ready to add series"), findsOneWidget);
      expect(find.text('Add series').evaluate().length, 1); // title only
    });

    testWidgets('options that cannot load show the error with retry', (
      tester,
    ) async {
      final api = addApi(results: [fakeLookup(1)])
        ..profilesResult = const Result.err(
          AppError(ErrorCategory.networkUnreachable),
        );
      await openSheet(tester, api);
      expect(find.text("Couldn't load the options"), findsOneWidget);
      api.profilesResult = const Result.ok([
        ArrQualityProfile(id: 4, name: 'HD-1080p'),
      ]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Quality profile'), findsOneWidget);
    });

    testWidgets('every locale and scale fits without overflow', (tester) async {
      final api = addApi(results: [fakeLookup(1)]);
      await pumpMatrix(
        tester,
        (v) => addApp(v, api, initialTerm: 'example'),
        variants: releaseVariants,
      );
      // Open the sheet in the last (ar, scale 2.0) variant too.
      await tester.tap(find.byType(MediaListTile).first);
      await tester.pumpAndSettle();
      expectNoFrameworkExceptions(tester);
    });
  });
}
