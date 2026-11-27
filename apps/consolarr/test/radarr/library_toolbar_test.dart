// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/sort_filter_chip_bar.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/presentation/library_page.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/radarr_screen.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

/// Profiles and tags cannot be read.
class _NoNamesApi extends FakeRadarrApi {
  _NoNamesApi({super.moviesResult});

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() async =>
      const Result.err(AppError(ErrorCategory.timeout));

  @override
  Future<Result<List<ArrTag>>> tags() async =>
      const Result.err(AppError(ErrorCategory.timeout));
}

/// Counts the tiles that are built (each asks for its poster once per build).
class _CountingSource extends ArtworkSource {
  _CountingSource(this.onPoster) : super(dio: Dio0.dio, api: FakeRadarrApi());
  final void Function() onPoster;
  @override
  ImageProvider? poster(RadarrMovie movie) {
    onPoster();
    return null;
  }
}

abstract final class Dio0 {
  static final dio = Dio();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RadarrScreen)));

void main() {
  group('filter chips (pure)', () {
    const f = MovieFilter(
      monitored: MonitoredFilter.monitored,
      file: FileFilter.missing,
      availability: {MinimumAvailability.tba, MinimumAvailability.released},
      qualityProfiles: {2, 3},
      tags: {5},
      collections: {'Example Collection'},
    );

    test('every criterion has a removable chip id', () {
      expect(activeFilterIds(f), [
        'monitored',
        'file',
        'availability:tba',
        'availability:released',
        'profile:2',
        'profile:3',
        'tag:5',
        'collection:Example Collection',
      ]);
    });

    test('removing a chip removes exactly that criterion', () {
      expect(removeFilter(f, 'monitored').monitored, MonitoredFilter.any);
      expect(removeFilter(f, 'file').file, FileFilter.any);
      expect(removeFilter(f, 'availability:tba').availability, {
        MinimumAvailability.released,
      });
      expect(removeFilter(f, 'profile:2').qualityProfiles, {3});
      expect(removeFilter(f, 'tag:5').tags, isEmpty);
      expect(
        removeFilter(f, 'collection:Example Collection').collections,
        isEmpty,
      );
      // The others stay.
      expect(removeFilter(f, 'tag:5').qualityProfiles, {2, 3});
      expect(removeFilter(f, 'unknown'), f);
    });

    test('the filter sheet selection round-trips', () {
      expect(filterFromSelection(filterSelection(f)), f);
      expect(
        filterFromSelection(filterSelection(MovieFilter.none)),
        MovieFilter.none,
      );
    });
  });

  group('grid extent', () {
    test('grows with the text scale and never shrinks below 2:3', () {
      expect(gridTileExtent(100, 1), 150);
      expect(gridTileExtent(100, 0.8), 150);
      expect(gridTileExtent(100, 2.2), greaterThan(gridTileExtent(100, 1.5)));
      expect(gridTileExtent(100, 2.2), greaterThan(200));
    });

    testWidgets('no clipping at the largest text scale', (tester) async {
      final max = harnessMatrix(
        sizes: const [Size(320, 568), Size(360, 800)],
        textScales: const [2.2, 3],
        locales: const [Locale('en'), Locale('ar'), Locale('en', 'XA')],
      );
      final api = FakeRadarrApi(
        moviesResult: Result.ok([
          for (var i = 1; i <= 6; i++)
            fakeMovie(
              i,
              title: 'Example Movie $i ${'Long Title ' * 6}',
              hasFile: i.isEven,
              digital: DateTime.utc(2030),
            ),
        ]),
      );
      // pumpMatrix fails on any overflow or framework exception.
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: max,
        verify: (v) async {
          final tile = tester.getSize(find.byType(PosterCard).first);
          expect(
            tile.height,
            greaterThanOrEqualTo(tile.width * 1.5),
            reason: v.label,
          );
          await expectAccessible(tester);
        },
      );
    });
  });

  group('search', () {
    testWidgets('is applied 150 ms after the last keystroke', (tester) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(5)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: phone,
      );
      final container = _container(tester);
      await tester.enterText(find.byType(EditableText), 'Movie 3');
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(libraryQueryProvider).search, '');
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(libraryQueryProvider).search, 'Movie 3');
      await tester.pumpAndSettle();
      expect(find.text('Example Movie 3'), findsOneWidget);
      expect(find.text('Example Movie 1'), findsNothing);
    });

    testWidgets('typing again restarts the wait; clearing is immediate', (
      tester,
    ) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(5)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: phone,
      );
      final container = _container(tester);
      await tester.enterText(find.byType(EditableText), 'Mo');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(EditableText), 'Movie 2');
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(libraryQueryProvider).search, '');
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(libraryQueryProvider).search, 'Movie 2');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(container.read(libraryQueryProvider).search, '');
    });
  });

  group('sheets', () {
    testWidgets('sort, filter and jump are glass sheets', (tester) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([
          for (var i = 0; i < 30; i++)
            fakeMovie(
              i + 1,
              title: '${String.fromCharCode(65 + i % 26)} Example Movie $i',
            ),
        ]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: phone,
      );
      for (final opener in [
        find.textContaining('Sort:'),
        find.textContaining('Filter'),
        find.byTooltip('Jump to'),
      ]) {
        await tester.tap(opener.first);
        await tester.pumpAndSettle();
        expect(find.byType(GlassSheet), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('applying a filter shows a chip that removes it', (
      tester,
    ) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([fakeMovie(1, hasFile: false), fakeMovie(2)]),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: phone,
      );
      final container = _container(tester);
      await container
          .read(libraryQueryProvider.notifier)
          .setFilter(const MovieFilter(file: FileFilter.missing));
      await tester.pumpAndSettle();
      expect(find.byType(ArrSortFilterBar), findsOneWidget);
      expect(find.text('Filter (1)'), findsOneWidget);
      expect(find.text('Example Movie 2'), findsNothing);
      await tester.tap(find.byTooltip('Remove filter File'));
      await tester.pumpAndSettle();
      expect(container.read(libraryQueryProvider).filter, MovieFilter.none);
      expect(find.text('Example Movie 2'), findsOneWidget);
    });
  });

  group('partial state: profiles and tags failed', () {
    testWidgets('the library still shows, says what is missing, can retry', (
      tester,
    ) async {
      final api = _NoNamesApi(moviesResult: Result.ok(fakeMovies(4)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: [...phone, ...stress],
        verify: (v) async {
          if (v.textScale == 1) {
            expect(find.text('Example Movie 1'), findsOneWidget);
          }
          if (v.textScale == 1) {
            expect(
              find.textContaining('Quality profiles could not be loaded'),
              findsOneWidget,
            );
          }
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('an active profile filter falls back to its number', (
      tester,
    ) async {
      final api = _NoNamesApi(moviesResult: Result.ok(fakeMovies(4)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: phone,
      );
      await _container(tester)
          .read(libraryQueryProvider.notifier)
          .setFilter(const MovieFilter(qualityProfiles: {1}));
      await tester.pumpAndSettle();
      expect(find.text('Profile 1'), findsOneWidget);
      // Sorting by profile still works without names (all last).
      expect(find.text('Example Movie 1'), findsOneWidget);
    });

    testWidgets('retry reads the lists again', (tester) async {
      var calls = 0;
      final api = _CountingProfilesApi(() => calls++)
        ..moviesResult = Result.ok(fakeMovies(2));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const RadarrScreen()),
        variants: phone,
      );
      final before = calls;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(before));
    });
  });

  group('large libraries', () {
    testWidgets('are filtered off the UI isolate; the old list stays', (
      tester,
    ) async {
      final gate = Completer<void>();
      var ran = 0;
      final api = FakeRadarrApi(
        moviesResult: Result.ok(fakeMovies(movieSyncLimit + 100)),
      );
      applyVariantView(tester, phone.single);
      await tester.pumpWidget(
        radarrApp(
          phone.single,
          api,
          const RadarrScreen(),
          movieRunner: <T>(T Function() c) async {
            ran++;
            await gate.future;
            return c();
          },
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ran, greaterThanOrEqualTo(1));
      expect(find.bySemanticsLabel('Updating the list…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Updating the list…'), findsNothing);
      expect(find.text('Example Movie 1'), findsOneWidget);
    });

    testWidgets('a small library is filtered inline', (tester) async {
      var ran = 0;
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(50)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          const RadarrScreen(),
          movieRunner: <T>(T Function() c) async {
            ran++;
            return c();
          },
        ),
        variants: phone,
      );
      expect(ran, 0);
      expect(find.text('Example Movie 1'), findsOneWidget);
    });

    testWidgets('scrolling 10,000 movies builds only what is shown', (
      tester,
    ) async {
      var builds = 0;
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(10000)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          const RadarrScreen(),
          artwork: _CountingSource(() => builds++),
        ),
        variants: phone,
      );
      final first = builds;
      expect(first, lessThan(80), reason: 'only the first screen is built');
      for (var i = 0; i < 20; i++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -600),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      // 20 screens of about 12 tiles each: each tile builds a bounded number
      // of times, never the whole library (10,000).
      expect(builds, lessThan(1500));
      expect(find.text('Example Movie 9999'), findsNothing);
    });
  });
}

/// Profiles fail; every read is counted.
class _CountingProfilesApi extends FakeRadarrApi {
  _CountingProfilesApi(this.onRead);
  final void Function() onRead;

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() async {
    onRead();
    return const Result.err(AppError(ErrorCategory.timeout));
  }
}
