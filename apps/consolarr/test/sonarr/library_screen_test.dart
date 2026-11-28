// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'library_harness.dart';
import 'support.dart';

const _phone = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

final _stress = harnessMatrix(
  sizes: const [Size(320, 568)],
  textScales: const [2],
  locales: const [Locale('ar'), Locale('en', 'XA')],
);

List<SonarrSeries> _named() => [
  fakeSeries(1, title: 'Alpha'),
  fakeSeries(2, title: 'Avocado', monitored: false),
  fakeSeries(3, title: 'Bravo'),
  fakeSeries(4, title: 'Charlie', status: SeriesStatus.ended),
];

Future<RouteRecorder> _pump(
  WidgetTester tester, {
  required LibraryData data,
  ArtworkSource? artwork,
  LibraryViewMode mode = LibraryViewMode.list,
  ScriptedSonarrApi? api,
  SonarrPrefsStore? prefs,
  HarnessVariant variant = _phone,
}) async {
  applyVariantView(tester, variant);
  final recorder = RouteRecorder();
  await tester.pumpWidget(
    libraryApp(
      variant,
      notifier: FakeLibraryNotifier(data),
      artwork: artwork,
      mode: mode,
      api: api,
      prefs: prefs,
      recorder: recorder,
    ),
  );
  await tester.pumpAndSettle();
  return recorder;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('series are grouped under pinned section headers', (
    tester,
  ) async {
    await _pump(tester, data: dataState(_named()));
    expect(find.bySemanticsLabel('Section A'), findsOneWidget);
    expect(find.bySemanticsLabel('Section B'), findsOneWidget);
    expect(find.bySemanticsLabel('Section C'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('R1: unreadable profiles or tags are shown with a retry, '
      'not silently hidden', (tester) async {
    final api = ScriptedSonarrApi()
      ..profilesResult = const Result.err(AppError(ErrorCategory.timeout));
    await _pump(tester, data: dataState(_named()), api: api);
    expect(
      find.textContaining('Quality profiles or tags could not be loaded'),
      findsOneWidget,
    );
    final before = api.count('qualityProfiles');
    api.profilesResult = const Result.ok([]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(api.count('qualityProfiles'), greaterThan(before));
    expect(
      find.textContaining('Quality profiles or tags could not be loaded'),
      findsNothing,
    );
  });

  testWidgets('R1: no notice while the lists load fine', (tester) async {
    await _pump(tester, data: dataState(_named()), api: ScriptedSonarrApi());
    expect(
      find.textContaining('Quality profiles or tags could not be loaded'),
      findsNothing,
    );
  });

  testWidgets('typing filters the list locally', (tester) async {
    await _pump(tester, data: dataState(_named()));
    await tester.enterText(find.byType(TextField), 'brav');
    await tester.pumpAndSettle();
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('no match offers to search for the text to add', (tester) async {
    final router = await _pump(tester, data: dataState(_named()));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No series match “zzz”'), findsOneWidget);
    await tester.tap(find.text('Search to add “zzz”'));
    await tester.pumpAndSettle();
    expect(router.location, '/sonarr/add?term=zzz');
  });

  testWidgets('filter-empty names the cause and clears the filters', (
    tester,
  ) async {
    final prefs = MemorySonarrPrefsStore()
      ..values['sonarr.srv1.library.filter'] =
          '{"monitored":"unmonitored","statuses":["upcoming"],"types":[],'
          '"profiles":[],"tags":[]}';
    await _pump(tester, data: dataState(_named()), prefs: prefs);
    expect(find.text('No series match your filters'), findsOneWidget);
    expect(find.text('Filter (2)'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
  });

  testWidgets('sort sheet changes the key and shows it on the chip', (
    tester,
  ) async {
    await _pump(tester, data: dataState(_named()));
    expect(find.text('Sort: Title'), findsOneWidget);
    await tester.tap(find.text('Sort: Title'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Rating'));
    await _tap(tester, find.text('Descending'));
    await _tap(tester, find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Sort: Rating'), findsOneWidget);
  });

  testWidgets('sort saved as default is stored per server', (tester) async {
    final prefs = MemorySonarrPrefsStore();
    await _pump(tester, data: dataState(_named()), prefs: prefs);
    await tester.tap(find.text('Sort: Title'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Year'));
    await _tap(tester, find.text('Save as default'));
    await _tap(tester, find.text('Apply'));
    await tester.pumpAndSettle();
    expect(prefs.values['sonarr.srv1.library.sort'], contains('year'));
  });

  testWidgets('filter sheet adds a removable chip', (tester) async {
    final api = ScriptedSonarrApi()
      ..profilesResult = const Result.ok([
        ArrQualityProfile(id: 1, name: 'HD-1080p'),
      ])
      ..tagsResult = const Result.ok([ArrTag(id: 4, label: 'kids')]);
    await _pump(tester, data: dataState(_named()), api: api);
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('HD-1080p'), findsOneWidget);
    expect(find.text('kids'), findsOneWidget);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.text('Unmonitored'),
      ),
    );
    await _tap(tester, find.text('Apply'));
    expect(
      find.byKey(const ValueKey('active-filter-monitored')),
      findsOneWidget,
    );
    expect(find.text('Avocado'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await tester.tap(find.byTooltip('Remove filter: Unmonitored'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('jump control scrolls to the chosen section', (tester) async {
    final many = [
      for (var i = 0; i < 40; i++)
        fakeSeries(i + 1, title: 'A show ${i.toString().padLeft(2, '0')}'),
      fakeSeries(100, title: 'Zulu'),
    ];
    await _pump(tester, data: dataState(many));
    expect(find.text('Zulu'), findsNothing);
    await tester.tap(find.byTooltip('Jump to section'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Z').last);
    await tester.pumpAndSettle();
    expect(find.text('Zulu'), findsOneWidget);
  });

  testWidgets('tapping a series opens its detail route', (tester) async {
    final router = await _pump(tester, data: dataState(_named()));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(router.location, '/sonarr/series/1');
  });

  testWidgets('the add button opens the add flow', (tester) async {
    final router = await _pump(tester, data: dataState(_named()));
    await tester.tap(find.byTooltip('Add a series'));
    await tester.pumpAndSettle();
    expect(router.location, '/sonarr/add');
  });

  testWidgets('an empty library offers to add a series', (tester) async {
    final router = await _pump(tester, data: dataState(const []));
    await tester.tap(find.text('Add a series').last);
    await tester.pumpAndSettle();
    expect(router.location, '/sonarr/add');
  });

  testWidgets('partial: unreadable rows are reported with their count', (
    tester,
  ) async {
    await _pump(
      tester,
      data: LibraryData(
        SeriesSnapshot(series: _named(), fetchedAt: fixedNow, skipped: 3),
      ),
    );
    expect(
      find.text("3 series couldn't be read and are not shown."),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('offline keeps the list under the age banner', (tester) async {
    await _pump(
      tester,
      data: dataState(
        _named(),
        offlineError: const AppError(ErrorCategory.networkUnreachable),
        age: const Duration(hours: 2),
      ),
    );
    expect(find.textContaining('2 hours ago'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  group('performance', () {
    testWidgets('10,000 series build only the visible tiles', (tester) async {
      final artwork = CountingArtworkSource();
      await _pump(
        tester,
        data: dataState(fakeSeriesList(10000)),
        artwork: artwork,
        mode: LibraryViewMode.grid,
      );
      expect(artwork.requests.length, lessThan(60));
    });

    testWidgets('sorting and filtering rebuild each visible tile a bounded '
        'number of times', (tester) async {
      final artwork = CountingArtworkSource();
      await _pump(
        tester,
        data: dataState(fakeSeriesList(200)),
        artwork: artwork,
        mode: LibraryViewMode.grid,
      );
      final visible = artwork.requests.length;
      artwork.requests.clear();
      await tester.tap(find.text('Sort: Title'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Descending'));
      await _tap(tester, find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'show 1');
      await tester.pumpAndSettle();
      final total = artwork.requests.values.fold<int>(0, (a, b) => a + b);
      expect(total, lessThan(visible * 4));
    });
  });

  group('every state is accessible and does not overflow', () {
    final states = <String, LibraryData Function()>{
      'groups': () => dataState(_named()),
      'partial': () => LibraryData(
        SeriesSnapshot(series: _named(), fetchedAt: fixedNow, skipped: 2),
      ),
      'offline': () => dataState(
        _named(),
        offlineError: const AppError(ErrorCategory.timeout),
        age: const Duration(minutes: 5),
      ),
    };
    for (final mode in LibraryViewMode.values) {
      for (final e in states.entries) {
        testWidgets('${mode.name} ${e.key}', (tester) async {
          await pumpMatrix(
            tester,
            (v) => libraryApp(
              v,
              notifier: FakeLibraryNotifier(e.value()),
              mode: mode,
            ),
            variants: _stress,
            verify: (v) => expectAccessible(tester),
          );
        });
      }
    }

    testWidgets('no-match', (tester) async {
      await pumpMatrix(
        tester,
        (v) =>
            libraryApp(v, notifier: FakeLibraryNotifier(dataState(_named()))),
        variants: _stress,
        verify: (v) async {
          await tester.enterText(find.byType(TextField), 'zzz');
          await tester.pumpAndSettle();
          await expectAccessible(tester);
        },
      );
    });
  });
}
