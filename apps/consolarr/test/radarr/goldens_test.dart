// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:consolarr/features/radarr/presentation/queue_page.dart';
import 'package:consolarr/features/radarr/presentation/radarr_screen.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

HarnessVariant _v(String lang, Brightness b) => HarnessVariant(
  size: const Size(360, 800),
  textScale: 1,
  locale: Locale(lang),
  brightness: b,
);

Future<void> _golden(
  WidgetTester tester,
  HarnessVariant v,
  FakeRadarrApi api,
  Widget child,
  String file, {
  MemoryPayloadCache? cache,
  RadarrLibraryMode? mode,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(radarrApp(v, api, child, cache: cache));
  await tester.pumpAndSettle();
  if (mode != null) {
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file'),
  );
}

enum RadarrLibraryMode { list }

void main() {
  final movies = [
    fakeMovie(1),
    fakeMovie(2, hasFile: false, digital: DateTime.utc(2026, 4)),
    fakeMovie(3, title: 'Example Movie With A Much Longer Title'),
    fakeMovie(4, hasFile: false, inCinemas: DateTime.utc(2027)),
    fakeMovie(5, monitored: false),
    fakeMovie(6, hasFile: false, inCinemas: DateTime.utc(2026, 4)),
  ];

  testWidgets('golden: library grid (en, dark)', (tester) async {
    await _golden(
      tester,
      _v('en', Brightness.dark),
      FakeRadarrApi(moviesResult: Result.ok(movies)),
      const RadarrScreen(),
      'radarr_library_grid_en_dark_360x800.png',
    );
  });

  testWidgets('golden: library list, offline (ar, light)', (tester) async {
    final cache = MemoryPayloadCache();
    await cache.write(
      'srv1',
      'radarr.movies',
      moviesJson(movies),
      fixedNow.subtract(const Duration(hours: 3)),
    );
    await _golden(
      tester,
      _v('ar', Brightness.light),
      FakeRadarrApi(
        moviesResult: const Result.err(
          AppError(ErrorCategory.networkUnreachable),
        ),
      ),
      const RadarrScreen(),
      'radarr_library_list_offline_ar_light_360x800.png',
      cache: cache,
      mode: RadarrLibraryMode.list,
    );
  });

  testWidgets('golden: movie detail (en, dark)', (tester) async {
    final m = RadarrMovie(
      id: 7,
      title: 'Example Movie',
      sortTitle: 'example movie',
      year: 2024,
      overview: 'A fictional film about nothing in particular.',
      monitored: true,
      hasFile: true,
      inCinemas: DateTime.utc(2026, 3),
      digitalRelease: DateTime.utc(2026, 4),
      qualityProfileId: 1,
      minimumAvailability: MinimumAvailability.released,
      collectionTitle: 'Example Collection',
      rating: 7.4,
      runtime: 101,
      genres: const ['Drama'],
      movieFile: const MovieFile(
        id: 1,
        size: 4 * 1024 * 1024 * 1024,
        qualityName: 'Bluray-1080p',
      ),
    );
    await _golden(
      tester,
      _v('en', Brightness.dark),
      FakeRadarrApi(moviesResult: Result.ok([m])),
      const MovieDetailScreen(movieId: 7),
      'radarr_detail_en_dark_360x800.png',
    );
  });

  testWidgets('golden: queue (en, dark)', (tester) async {
    await _golden(
      tester,
      _v('en', Brightness.dark),
      FakeRadarrApi()
        ..queueResult = const Result.ok([
          ArrQueueItem(
            id: 1,
            movieId: 7,
            title: 'Example.Movie.2024.1080p',
            state: ArrQueueState.downloading,
            size: 1000,
            sizeLeft: 400,
            timeLeft: Duration(minutes: 12),
          ),
          ArrQueueItem(
            id: 2,
            title: 'Other.Movie.2023',
            state: ArrQueueState.importPending,
            size: 1000,
            sizeLeft: 0,
          ),
        ]),
      const QueuePage(
        padding: EdgeInsets.fromLTRB(16, 60, 16, 88),
        active: false,
      ),
      'radarr_queue_en_dark_360x800.png',
    );
  });
}
