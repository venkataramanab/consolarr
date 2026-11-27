// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/features/radarr/presentation/missing_page.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:consolarr/features/radarr/presentation/queue_page.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

bool _en(HarnessVariant v) => v.locale == const Locale('en');

const _pad = EdgeInsets.fromLTRB(16, 60, 16, 88);
final _both = [...phone, ...stress];

RadarrMovie _detailMovie({bool file = true}) => RadarrMovie(
  id: 7,
  title: 'Example Movie',
  sortTitle: 'example movie',
  year: 2024,
  overview: 'A fictional film about nothing in particular.',
  monitored: true,
  hasFile: file,
  inCinemas: DateTime.utc(2026, 3),
  digitalRelease: DateTime.utc(2026, 4),
  qualityProfileId: 1,
  minimumAvailability: MinimumAvailability.released,
  collectionTitle: 'Example Collection',
  youTubeTrailerId: 'abcDEF12345',
  rating: 7.4,
  runtime: 101,
  genres: const ['Drama'],
  movieFile: file
      ? MovieFile(id: 1, size: 4 << 30, qualityName: 'Bluray-1080p')
      : null,
);

Future<void> _pumpDetail(
  WidgetTester tester,
  FakeRadarrApi api, {
  MemoryPayloadCache? cache,
  List<HarnessVariant>? variants,
  Future<void> Function(HarnessVariant)? verify,
}) => pumpMatrix(
  tester,
  (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7), cache: cache),
  variants: variants ?? _both,
  verify: verify ?? (v) => expectAccessible(tester),
);

void main() {
  group('movie detail (RAD-08)', () {
    testWidgets('data: banner, file info, collection as plain text, trailer', (
      tester,
    ) async {
      final api = FakeRadarrApi(moviesResult: Result.ok([_detailMovie()]));
      await _pumpDetail(
        tester,
        api,
        variants: phone,
        verify: (v) async {
          expect(find.textContaining('Released digitally'), findsWidgets);
          expect(find.textContaining('Bluray-1080p'), findsWidgets);
          expect(
            find.text('Part of the collection Example Collection'),
            findsOneWidget,
          );
          expect(
            find.textContaining('youtube.com/watch?v=abcDEF12345'),
            findsOneWidget,
          );
          expect(find.byTooltip('Copy trailer link'), findsOneWidget);
        },
      );
      await _pumpDetail(tester, api, variants: stress);
    });

    testWidgets('no file says so', (tester) async {
      final api = FakeRadarrApi(
        moviesResult: Result.ok([_detailMovie(file: false)]),
      );
      await _pumpDetail(
        tester,
        api,
        variants: phone,
        verify: (v) async =>
            expect(find.textContaining('No file yet'), findsOneWidget),
      );
    });

    testWidgets('loading shows a skeleton', (tester) async {
      final api = _Slow();
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MovieDetailScreen(movieId: 7)),
        variants: phone,
      );
      expect(find.bySemanticsLabel('Loading movies'), findsOneWidget);
    });

    for (final c in ErrorCategory.values) {
      testWidgets('error ${c.code}', (tester) async {
        final api = FakeRadarrApi()..movieResult = Result.err(AppError(c));
        await _pumpDetail(tester, api);
      });
    }

    testWidgets('a deleted movie says it no longer exists', (tester) async {
      final api = FakeRadarrApi()
        ..movieResult = const Result.err(AppError(ErrorCategory.notFound));
      await _pumpDetail(
        tester,
        api,
        variants: phone,
        verify: (v) async =>
            expect(find.text('This movie no longer exists'), findsOneWidget),
      );
    });

    testWidgets('offline: cached data, age banner, writes disabled', (
      tester,
    ) async {
      final cache = MemoryPayloadCache();
      await cache.write(
        'srv1',
        'radarr.movie.7',
        '${_detailMovie().toJson().toString().isEmpty ? '' : ''}'
            '${moviesJson([_detailMovie()]).replaceFirst('[', '').replaceFirst(RegExp(r'\]$'), '')}',
        fixedNow.subtract(const Duration(hours: 2)),
      );
      final api = FakeRadarrApi()
        ..movieResult = const Result.err(AppError(ErrorCategory.timeout));
      await _pumpDetail(
        tester,
        api,
        cache: cache,
        variants: [...phone, ...stress],
        verify: (v) async {
          if (v.textScale == 1) {
            expect(find.textContaining('Updated 2 hours ago'), findsOneWidget);
            final search = tester.widget<FilledButton>(
              find.ancestor(
                of: find.text('Search'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              ),
            );
            expect(search.onPressed, isNull);
            expect(find.textContaining('Changes are disabled'), findsWidgets);
          }
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('automatic search shows inline progress to the end', (
      tester,
    ) async {
      final api = FakeRadarrApi(moviesResult: Result.ok([_detailMovie()]));
      await _pumpDetail(tester, api, variants: phone);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('search [7]'));
      expect(find.text('Search finished'), findsOneWidget);
    });
  });

  group('calendar (RAD-10)', () {
    final movies = [
      fakeMovie(1, title: 'Cinema One', inCinemas: DateTime.utc(2026, 5, 3)),
      fakeMovie(2, title: 'Digital Two', digital: DateTime.utc(2026, 5, 3)),
      fakeMovie(3, title: 'Disc Three', physical: DateTime.utc(2026, 6, 1)),
    ];

    testWidgets('lists releases by day and filters by type', (tester) async {
      final api = FakeRadarrApi()..calendarResult = Result.ok(movies);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
        variants: [...phone, ...stress],
        verify: (v) => expectAccessible(tester),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
        variants: phone,
      );
      expect(find.text('Cinema One'), findsOneWidget);
      await tester.tap(find.text('Cinema').first);
      await tester.pumpAndSettle();
      expect(find.text('Cinema One'), findsNothing);
      expect(find.text('Digital Two'), findsOneWidget);
    });

    testWidgets('empty', (tester) async {
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, FakeRadarrApi(), const CalendarPage(padding: _pad)),
        variants: _both,
        verify: (v) async {
          if (_en(v))
            expect(find.text('No releases in this period'), findsOneWidget);
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('offline with cache', (tester) async {
      final cache = MemoryPayloadCache();
      await cache.write(
        'srv1',
        'radarr.calendar',
        moviesJson(movies),
        fixedNow.subtract(const Duration(minutes: 30)),
      );
      final api = FakeRadarrApi()
        ..calendarResult = const Result.err(
          AppError(ErrorCategory.networkUnreachable),
        );
      await pumpMatrix(
        tester,
        (v) =>
            radarrApp(v, api, const CalendarPage(padding: _pad), cache: cache),
        variants: _both,
        verify: (v) async {
          if (_en(v)) {
            expect(
              find.textContaining('Updated 30 minutes ago'),
              findsOneWidget,
            );
          }
          await expectAccessible(tester);
        },
      );
    });

    for (final c in ErrorCategory.values) {
      testWidgets('error ${c.code}', (tester) async {
        final api = FakeRadarrApi()..calendarResult = Result.err(AppError(c));
        await pumpMatrix(
          tester,
          (v) => radarrApp(v, api, const CalendarPage(padding: _pad)),
          variants: _both,
          verify: (v) => expectAccessible(tester),
        );
      });
    }
  });

  group('queue (RAD-11)', () {
    final items = [
      const RadarrQueueItem(
        id: 1,
        movieId: 7,
        title: 'Example.Movie.2024.1080p',
        status: 'downloading',
        size: 1000,
        sizeLeft: 400,
        timeLeft: Duration(minutes: 12),
        downloadClient: 'Example Client',
      ),
      const RadarrQueueItem(
        id: 2,
        movieId: 8,
        title: 'Other.Movie.2023',
        status: 'completed',
        trackedStatus: 'warning',
        trackedState: 'importPending',
        size: 1000,
        messages: ['No files found are eligible for import'],
      ),
      const RadarrQueueItem(id: 3, status: 'paused', size: 10),
      const RadarrQueueItem(
        id: 4,
        status: 'downloadClientUnavailable',
        size: 10,
      ),
    ];

    testWidgets('rows read progress in words', (tester) async {
      final api = FakeRadarrApi()..queueResult = Result.ok(items);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const QueuePage(padding: _pad, active: false)),
        variants: _both,
        verify: (v) => expectAccessible(tester),
      );
      expect(find.text('Example.Movie.2024.1080p'), findsOneWidget);
    });

    testWidgets('empty and every error', (tester) async {
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          FakeRadarrApi(),
          const QueuePage(padding: _pad, active: false),
        ),
        variants: _both,
        verify: (v) async {
          if (_en(v))
            expect(find.text('Nothing is downloading'), findsOneWidget);
          await expectAccessible(tester);
        },
      );
    });

    for (final c in ErrorCategory.values) {
      testWidgets('error ${c.code}', (tester) async {
        final api = FakeRadarrApi()..queueResult = Result.err(AppError(c));
        await pumpMatrix(
          tester,
          (v) =>
              radarrApp(v, api, const QueuePage(padding: _pad, active: false)),
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      });
    }

    testWidgets('removal asks, states the consequence, and sends the choice', (
      tester,
    ) async {
      final api = FakeRadarrApi()..queueResult = Result.ok(items);
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const QueuePage(padding: _pad, active: false)),
        variants: phone,
      );
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove from queue'), findsOneWidget);
      expect(
        find.textContaining('deleted from the download client'),
        findsOneWidget,
      );
      await tester.tap(find.text('Blocklist and search again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('searches for another one'), findsOneWidget);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(api.calls.single, 'remove 1 client=true blocklistAndSearch');
      expect(find.text('Example.Movie.2024.1080p'), findsNothing);
    });

    testWidgets('cancel sends nothing; failure keeps the row', (tester) async {
      final api = FakeRadarrApi()
        ..queueResult = Result.ok(items)
        ..removeResult = const Result.err(AppError(ErrorCategory.serverError));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const QueuePage(padding: _pad, active: false)),
        variants: phone,
      );
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not remove'), findsOneWidget);
      expect(find.text('Example.Movie.2024.1080p'), findsOneWidget);
    });
  });

  group('missing and upcoming (RAD-15)', () {
    final lib = [
      fakeMovie(
        1,
        title: 'Released Missing',
        hasFile: false,
        digital: DateTime.utc(2026, 4),
      ),
      fakeMovie(
        2,
        title: 'Upcoming One',
        hasFile: false,
        inCinemas: DateTime.utc(2027),
      ),
      fakeMovie(3, title: 'Has File'),
    ];

    testWidgets('scopes split released from upcoming', (tester) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(lib));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: _both,
        verify: (v) => expectAccessible(tester),
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      expect(find.text('Released Missing'), findsOneWidget);
      expect(find.text('Upcoming One'), findsNothing);
      await tester.tap(find.text('Upcoming'));
      await tester.pumpAndSettle();
      expect(find.text('Upcoming One'), findsOneWidget);
      expect(find.text('Has File'), findsNothing);
    });

    testWidgets('empty-good state', (tester) async {
      final api = FakeRadarrApi(moviesResult: Result.ok([fakeMovie(1)]));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: _both,
        verify: (v) async {
          if (_en(v)) expect(find.text('Nothing is missing'), findsOneWidget);
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('per-row search shows progress; search all confirms first', (
      tester,
    ) async {
      final api = FakeRadarrApi(moviesResult: Result.ok(lib));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, api, const MissingPage(padding: _pad)),
        variants: phone,
      );
      await tester.tap(find.byTooltip('Search for Released Missing'));
      await tester.pumpAndSettle();
      expect(api.calls, ['search [1]']);
      expect(find.textContaining('Search finished'), findsOneWidget);

      await tester.tap(find.text('Search all missing'));
      await tester.pumpAndSettle();
      expect(find.textContaining('indexer requests'), findsOneWidget);
      expect(api.calls, hasLength(1), reason: 'nothing sent before confirm');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, hasLength(1));
      await tester.tap(find.text('Search all missing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search all'));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'searchAll');
    });

    testWidgets('offline disables searches', (tester) async {
      final cache = MemoryPayloadCache();
      await cache.write(
        'srv1',
        'radarr.movies',
        moviesJson(lib),
        fixedNow.subtract(const Duration(hours: 1)),
      );
      final api = FakeRadarrApi(
        moviesResult: const Result.err(AppError(ErrorCategory.timeout)),
      );
      await pumpMatrix(
        tester,
        (v) =>
            radarrApp(v, api, const MissingPage(padding: _pad), cache: cache),
        variants: phone,
      );
      expect(find.textContaining('Updated 1 hour ago'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.search).first,
      );
      expect(button.onPressed, isNull);
    });
  });

  group('trailer links', () {
    test('only plausible ids build a YouTube URL', () {
      expect(
        trailerUri('abcDEF12345').toString(),
        'https://www.youtube.com/watch?v=abcDEF12345',
      );
      for (final bad in [
        null,
        '',
        'a b',
        'x/../y',
        'http://evil.example/x',
        'javascript:alert(1)',
        'a' * 64,
      ]) {
        expect(trailerUri(bad), isNull, reason: '$bad');
      }
    });
  });
}

class _Slow extends FakeRadarrApi {
  final Completer<void> never = Completer();
  @override
  Future<Result<RadarrMovie>> movie(int id) async {
    await never.future;
    throw StateError('unreachable');
  }
}
