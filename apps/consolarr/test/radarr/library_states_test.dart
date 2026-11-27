// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/presentation/radarr_screen.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

Map<String, FakeRadarrApi Function()> _states() => {
  'data': () => FakeRadarrApi(moviesResult: Result.ok(fakeMovies(12))),
  'empty': () => FakeRadarrApi(),
  'long titles': () => FakeRadarrApi(
    moviesResult: Result.ok([
      for (var i = 1; i <= 6; i++)
        fakeMovie(i, title: 'Example Movie $i ${'Very Long Title ' * 12}'),
    ]),
  ),
  'availability mix': () => FakeRadarrApi(
    moviesResult: Result.ok([
      fakeMovie(1, hasFile: false),
      fakeMovie(2, hasFile: false, inCinemas: DateTime.utc(2026, 4)),
      fakeMovie(3, hasFile: false, digital: DateTime.utc(2026, 4)),
      fakeMovie(4, hasFile: false, physical: DateTime.utc(2026, 4)),
      fakeMovie(5, hasFile: false, inCinemas: DateTime.utc(2027)),
      fakeMovie(6, monitored: false),
    ]),
  ),
  for (final c in ErrorCategory.values)
    'error ${c.code}': () =>
        FakeRadarrApi(moviesResult: Result.err(AppError(c))),
};

void main() {
  group('every state: no overflow and accessible', () {
    for (final entry in _states().entries) {
      testWidgets(entry.key, (tester) async {
        await pumpMatrix(
          tester,
          (v) => radarrApp(v, entry.value(), const RadarrScreen()),
          variants: [...phone, ...stress],
          verify: (v) => expectAccessible(tester),
        );
      });
    }
  });

  testWidgets('loading shows a skeleton, not data', (tester) async {
    final api = _LoadingApi();
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const RadarrScreen()),
      variants: phone,
    );
    expect(find.bySemanticsLabel('Loading movies'), findsOneWidget);
    expect(find.text('Example Movie 1'), findsNothing);
  });

  testWidgets('offline with cache shows the age banner and the data', (
    tester,
  ) async {
    final cache = MemoryPayloadCache();
    await cache.write(
      'srv1',
      'radarr.movies',
      moviesJson(fakeMovies(3)),
      fixedNow.subtract(const Duration(hours: 3)),
    );
    final api = FakeRadarrApi(
      moviesResult: const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      ),
    );
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const RadarrScreen(), cache: cache),
      variants: [...phone, ...stress],
      verify: (v) async {
        if (v.textScale == 1) {
          expect(find.text('Example Movie 1'), findsOneWidget);
          expect(find.textContaining('Updated 3 hours ago'), findsOneWidget);
        }
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('empty library offers to add a movie', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, FakeRadarrApi(), const RadarrScreen()),
      variants: phone,
    );
    expect(find.text('No movies yet'), findsOneWidget);
    expect(find.text('Add movie'), findsWidgets);
  });

  testWidgets('no match offers search to add', (tester) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(
        v,
        FakeRadarrApi(moviesResult: Result.ok(fakeMovies(3))),
        const RadarrScreen(),
      ),
      variants: phone,
    );
    await tester.enterText(find.byType(EditableText), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No movie matches'), findsOneWidget);
    expect(find.text('Search to add'), findsOneWidget);
  });

  testWidgets('filters that hide everything say so and can be cleared', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => radarrApp(
        v,
        FakeRadarrApi(moviesResult: Result.ok(fakeMovies(3))),
        const RadarrScreen(),
      ),
      variants: phone,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadarrScreen)),
    );
    await container
        .read(libraryQueryProvider.notifier)
        .setFilter(const MovieFilter(file: FileFilter.missing));
    await tester.pumpAndSettle();
    expect(find.text('Filters hide every movie'), findsOneWidget);
    await tester.tap(find.text('Clear filters').last);
    await tester.pumpAndSettle();
    expect(find.text('Example Movie 1'), findsOneWidget);
  });

  testWidgets('list mode and grid mode show the same movies', (tester) async {
    final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(4)));
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const RadarrScreen()),
      variants: phone,
    );
    expect(find.text('Example Movie 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();
    expect(find.text('Example Movie 1'), findsOneWidget);
    expect(find.text('Example Movie 4'), findsOneWidget);
  });

  testWidgets('10,000 movies build lazily', (tester) async {
    final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(10000)));
    await pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const RadarrScreen()),
      variants: phone,
    );
    final tiles =
        find.byType(Image).evaluate().length +
        find.byType(Semantics).evaluate().length;
    expect(tiles, lessThan(2000));
    expect(find.text('Example Movie 9999'), findsNothing);
  });

  testWidgets('sheets: sort, filter and jump open with a close button', (
    tester,
  ) async {
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
    for (final tap in [
      find.textContaining('Sort:'),
      find.textContaining('Filter'),
      find.byTooltip('Jump to'),
    ]) {
      await tester.tap(tap.first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsOneWidget, reason: '$tap');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }
  });
}

class _LoadingApi extends FakeRadarrApi {
  final Completer<void> never = Completer();
  @override
  Future<Result<List<RadarrMovie>>> movies() async {
    await never.future;
    return const Result.ok([]);
  }
}
