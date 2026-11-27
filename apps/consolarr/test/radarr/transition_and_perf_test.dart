// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/domain/release_query.dart';
import 'package:consolarr/features/radarr/domain/wanted.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/radarr_screen.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

/// Which fake server is active; changing it is a "server switch".
class _Active extends Notifier<String> {
  @override
  String build() => 'a';
  void set(String v) => state = v;
}

final _activeProvider = NotifierProvider<_Active, String>(_Active.new);

class _GatedApi extends FakeRadarrApi {
  _GatedApi(Result<List<RadarrMovie>> result, [this.gate])
    : super(moviesResult: result);
  final Completer<void>? gate;
  @override
  Future<Result<List<RadarrMovie>>> movies() async {
    await gate?.future;
    return super.movies();
  }
}

void main() {
  group('provider transitions with the real providers (docs/patterns §3)', () {
    Future<(ProviderContainer, Completer<void>)> pump(
      WidgetTester tester, {
      required Result<List<RadarrMovie>> second,
    }) async {
      final gate = Completer<void>();
      final apis = {
        'a': FakeRadarrApi(
          moviesResult: Result.ok([fakeMovie(1, title: 'Alpha Movie')]),
        ),
        'b': _GatedApi(second, gate),
      };
      late ProviderContainer container;
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          FakeRadarrApi(),
          Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const RadarrScreen();
            },
          ),
          includeContext: false,
          extra: [
            radarrContextProvider.overrideWith((ref) async {
              final id = ref.watch(_activeProvider);
              return contextFor(apis[id]!);
            }),
          ],
        ),
        variants: phone,
      );
      return (container, gate);
    }

    testWidgets('a reload shows the skeleton, never the previous server', (
      tester,
    ) async {
      final (container, gate) = await pump(
        tester,
        second: Result.ok([fakeMovie(2, title: 'Beta Movie')]),
      );
      expect(find.text('Alpha Movie'), findsOneWidget);
      container.read(_activeProvider.notifier).set('b');
      await tester.pump();
      await tester.pump();
      expect(find.text('Alpha Movie'), findsNothing);
      expect(find.bySemanticsLabel('Loading movies'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Beta Movie'), findsOneWidget);
      expect(find.text('Alpha Movie'), findsNothing);
    });

    testWidgets('an error on the new server shows the error, not old data', (
      tester,
    ) async {
      final (container, gate) = await pump(
        tester,
        second: const Result.err(AppError(ErrorCategory.authFailed)),
      );
      container.read(_activeProvider.notifier).set('b');
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Alpha Movie'), findsNothing);
      expect(find.text("Couldn't load your movies"), findsOneWidget);
    });
  });

  group('performance', () {
    testWidgets('posters and backdrop decode at display size', (tester) async {
      final source = _RecordingSource();
      final m = fakeMovie(1);
      late int width;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 100,
              child: Builder(
                builder: (context) {
                  final img = movieArtwork(source, m, 200) as Image;
                  final provider = img.image as ResizeImage;
                  width = provider.width!;
                  return img;
                },
              ),
            ),
          ),
        ),
      );
      expect(width, 200, reason: 'cacheWidth passed through, not full size');
    });

    testWidgets('tiles are not rebuilt when unrelated state changes', (
      tester,
    ) async {
      var builds = 0;
      final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(40)));
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          Consumer(
            builder: (context, ref, _) {
              ref.watch(searchStatusProvider);
              return const RadarrScreen();
            },
          ),
          artwork: _CountingSource(() => builds++),
        ),
        variants: phone,
      );
      final before = builds;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RadarrScreen)),
      );
      // Unrelated provider traffic (a search on another movie).
      unawaited(container.read(searchStatusProvider.notifier).searchMovie(3));
      await tester.pumpAndSettle();
      expect(builds - before, lessThan(5));
    });

    test('big library and release payloads are parsed through the runner', () {
      // Covered by the arr_api client tests (isolate threshold); this guards
      // the constant the app relies on.
      expect(ArrClientBase.isolateThresholdBytes, 64 * 1024);
    });
  });

  group('domain', () {
    test('wanted scopes split by availability and drop movies with files', () {
      final now = DateTime.utc(2026, 5, 1);
      final lib = [
        fakeMovie(1, hasFile: false, digital: DateTime.utc(2026, 4)),
        fakeMovie(2, hasFile: false, inCinemas: DateTime.utc(2027)),
        fakeMovie(3, hasFile: false, monitored: false),
        fakeMovie(4),
        fakeMovie(5, hasFile: false),
      ];
      List<int> ids(WantedScope s) => [
        for (final m in wantedMovies(lib, s, now)) m.id,
      ];
      expect(ids(WantedScope.released), [1]);
      expect(ids(WantedScope.upcoming), [2, 5]);
      expect(ids(WantedScope.allMissing), [1, 2, 5]);
    });

    test('release sort and filter', () {
      const a = ArrRelease(
        guid: 'a',
        indexerId: 1,
        title: 'A',
        size: 3,
        ageMinutes: 600,
        seeders: 5,
        resolution: 1080,
        protocol: ArrProtocol.torrent,
        indexer: 'x',
      );
      const b = ArrRelease(
        guid: 'b',
        indexerId: 1,
        title: 'B',
        size: 9,
        ageMinutes: 120,
        seeders: 50,
        resolution: 720,
        protocol: ArrProtocol.usenet,
        indexer: 'y',
        approved: false,
        rejections: ['r'],
      );
      List<String> ids(
        ReleaseSortKey k, [
        ReleaseFilter f = const ReleaseFilter(),
      ]) => [
        for (final r in applyReleaseQuery([a, b], k, f)) r.guid,
      ];
      expect(ids(ReleaseSortKey.bestMatch), [
        'a',
        'b',
      ], reason: 'accepted first');
      expect(ids(ReleaseSortKey.size), ['b', 'a']);
      expect(ids(ReleaseSortKey.age), ['b', 'a'], reason: 'newest first');
      expect(ids(ReleaseSortKey.seeders), ['b', 'a']);
      expect(ids(ReleaseSortKey.quality), ['a', 'b']);
      expect(
        ids(
          ReleaseSortKey.bestMatch,
          const ReleaseFilter(acceptance: ReleaseAcceptance.rejected),
        ),
        ['b'],
      );
      expect(
        ids(ReleaseSortKey.bestMatch, const ReleaseFilter(protocol: 'torrent')),
        ['a'],
      );
      expect(
        ids(ReleaseSortKey.bestMatch, const ReleaseFilter(resolution: 720)),
        ['b'],
      );
      expect(
        ids(ReleaseSortKey.bestMatch, const ReleaseFilter(text: 'zz')),
        isEmpty,
      );
    });

    test('group offsets accumulate header and row extents', () {
      final movies = [
        for (var i = 0; i < 10; i++) fakeMovie(i + 1, title: 'A$i'),
        for (var i = 0; i < 4; i++) fakeMovie(100 + i, title: 'B$i'),
      ];
      final groups = [
        MovieGroup('A', movies.sublist(0, 10)),
        MovieGroup('B', movies.sublist(10)),
      ];
      final list = groupOffsets(groups, grid: false, width: 328, textScale: 1);
      expect(list[0], 0);
      expect(list[1], groupHeaderHeight + 10 * listRowExtent(1));
      final grid = groupOffsets(groups, grid: true, width: 328, textScale: 1);
      expect(grid[1], greaterThan(groupHeaderHeight));
    });
  });
}

class _RecordingSource extends ArtworkSource {
  _RecordingSource() : super(dio: Dio0.dio, api: FakeRadarrApi());
  @override
  ImageProvider? poster(RadarrMovie movie) => MemoryImage(Uint8List(0));
}

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
