// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:consolarr/features/radarr/presentation/calendar_page.dart';
import 'package:consolarr/features/radarr/presentation/edit_sheet.dart';
import 'package:consolarr/features/radarr/presentation/missing_page.dart';
import 'package:consolarr/features/radarr/presentation/movie_detail_screen.dart';
import 'package:consolarr/features/radarr/presentation/release_sheet.dart';
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

  group('edit sheet (RAD-09)', () {
    testWidgets('saves monitored/profile/availability/tags, never the path', (
      tester,
    ) async {
      final api = FakeRadarrApi(moviesResult: Result.ok([_detailMovie()]));
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          Consumer(
            builder: (context, ref, _) {
              ref.watch(movieDetailProvider(7));
              return Center(
                child: FilledButton(
                  onPressed: () => showEditSheet(context, _detailMovie()),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
        variants: phone,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit movie'), findsOneWidget);
      expect(find.textContaining('Root folder'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.calls.single, contains('monitored=false'));
      expect(find.text('Edit movie'), findsNothing);
    });

    testWidgets('failure keeps the sheet and says why', (tester) async {
      final api = FakeRadarrApi(moviesResult: Result.ok([_detailMovie()]))
        ..updateResult = const Result.err(AppError(ErrorCategory.serverError));
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          Consumer(
            builder: (context, ref, _) {
              ref.watch(movieDetailProvider(7));
              return FilledButton(
                onPressed: () => showEditSheet(context, _detailMovie()),
                child: const Text('open'),
              );
            },
          ),
        ),
        variants: [...phone, ...stress],
        verify: (v) async {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(FilledButton).last);
          await tester.tap(find.byType(FilledButton).last);
          await tester.pumpAndSettle();
          if (_en(v)) {
            expect(find.textContaining('Could not save'), findsOneWidget);
          }
          await expectAccessible(tester);
        },
      );
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

  group('release sheet (RAD-13)', () {
    final releases = [
      const RadarrRelease(
        guid: 'a',
        indexerId: 1,
        title: 'Example.Movie.2024.1080p.WEB',
        size: 4 << 30,
        ageHours: 5,
        seeders: 40,
        protocol: 'torrent',
        qualityName: 'WEBDL-1080p',
        resolution: 1080,
        indexer: 'Example Indexer',
      ),
      const RadarrRelease(
        guid: 'b',
        indexerId: 1,
        title: 'Example.Movie.2024.720p.CAM',
        size: 1 << 30,
        ageHours: 100,
        seeders: 2,
        protocol: 'usenet',
        resolution: 720,
        approved: false,
        rejections: ['Quality is not wanted', 'Not an upgrade'],
        customFormats: ['x265'],
      ),
    ];

    Future<void> pumpSheet(
      WidgetTester tester,
      FakeRadarrApi api, {
      List<HarnessVariant>? variants,
      Future<void> Function(HarnessVariant)? verify,
    }) => pumpMatrix(
      tester,
      (v) => radarrApp(v, api, const ReleaseSheetBody(movieId: 7)),
      variants: variants ?? phone,
      verify: verify,
    );

    testWidgets('lists, sorts, filters', (tester) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(releases);
      await pumpSheet(
        tester,
        api,
        variants: _both,
        verify: (v) => expectAccessible(tester),
      );
      await pumpSheet(tester, api);
      expect(find.text('Example.Movie.2024.1080p.WEB'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Rejected'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rejected'));
      await tester.pumpAndSettle();
      expect(find.text('Example.Movie.2024.1080p.WEB'), findsNothing);
      expect(find.text('Example.Movie.2024.720p.CAM'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Accepted'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Accepted'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('720p'));
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(find.text('No release matches'), findsOneWidget);
    });

    testWidgets('none found, searching and errors', (tester) async {
      await pumpSheet(
        tester,
        FakeRadarrApi(),
        variants: _both,
        verify: (v) async {
          if (_en(v)) expect(find.text('No releases found'), findsOneWidget);
          await expectAccessible(tester);
        },
      );
    });

    for (final c in ErrorCategory.values) {
      testWidgets('error ${c.code}', (tester) async {
        final api = FakeRadarrApi()..releasesResult = Result.err(AppError(c));
        await pumpSheet(
          tester,
          api,
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      });
    }

    testWidgets('grabbing an accepted release sends it directly', (
      tester,
    ) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(releases);
      await pumpSheet(tester, api);
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(api.calls, ['grab a']);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('a rejected release needs a confirm that shows the reasons', (
      tester,
    ) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(releases);
      await pumpSheet(tester, api);
      await tester.tap(find.text('Download').last);
      await tester.pumpAndSettle();
      expect(find.text('Download a rejected release?'), findsOneWidget);
      expect(find.textContaining('Not an upgrade'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      await tester.tap(find.text('Download').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download anyway'));
      await tester.pumpAndSettle();
      expect(api.calls, ['grab b']);
    });

    testWidgets('grab failure shows retry', (tester) async {
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok(releases)
        ..grabResult = const Result.err(AppError(ErrorCategory.serverError));
      await pumpSheet(tester, api);
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not send'), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
    });

    testWidgets('expanding shows rejection reasons and custom formats', (
      tester,
    ) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(releases);
      await pumpSheet(tester, api);
      await tester.tap(find.text('Details').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Quality is not wanted'), findsOneWidget);
      expect(find.text('x265'), findsOneWidget);
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

  group('add movie (RAD-14)', () {
    final results = [
      RadarrMovie(
        id: 0,
        title: 'New Movie',
        sortTitle: 'new movie',
        year: 2025,
        tmdbId: 11,
        collectionTitle: 'Example Saga',
      ),
      RadarrMovie(
        id: 5,
        title: 'Known Movie',
        sortTitle: 'known movie',
        year: 2020,
        tmdbId: 12,
      ),
      const RadarrMovie(
        id: 0,
        title: 'Plain Movie',
        sortTitle: 'plain movie',
        tmdbId: 13,
      ),
    ];

    FakeRadarrApi api() => FakeRadarrApi()
      ..lookupResult = Result.ok(results)
      ..rootFoldersResult = [const ArrRootFolder(id: 1, path: '/movies')];

    testWidgets('lookup shows the in-library marker; add sends the options', (
      tester,
    ) async {
      final a = api();
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, a, const AddMovieScreen(initialTerm: 'movie')),
        variants: phone,
      );
      expect(find.text('In library'), findsOneWidget);
      await tester.tap(find.text('New Movie'));
      await tester.pumpAndSettle();
      // The collection switch only exists because this lookup has one.
      expect(find.text('Also add the rest of the collection'), findsOneWidget);
      await tester.tap(find.text('Also add the rest of the collection'));
      await tester.pump();
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pumpAndSettle();
      expect(
        a.calls.singleWhere((c) => c.startsWith('add')),
        'add search=true collection=true root=/movies',
      );
      expect(find.text('Movie added'), findsOneWidget);
    });

    testWidgets('no collection switch without a collection', (tester) async {
      final a = api();
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, a, const AddMovieScreen(initialTerm: 'movie')),
        variants: phone,
      );
      await tester.tap(find.text('Plain Movie'));
      await tester.pumpAndSettle();
      expect(find.text('Also add the rest of the collection'), findsNothing);
    });

    testWidgets('remembered root folder is preselected', (tester) async {
      final a = api()
        ..rootFoldersResult = [
          const ArrRootFolder(id: 1, path: '/movies'),
          const ArrRootFolder(id: 2, path: '/movies-4k'),
        ];
      final prefs = MemoryPrefs()
        ..values['radarr.srv1.default_root_folder'] = '/movies-4k';
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          a,
          const AddMovieScreen(initialTerm: 'movie'),
          prefs: prefs,
        ),
        variants: phone,
      );
      await tester.tap(find.text('Plain Movie'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pumpAndSettle();
      expect(
        a.calls.singleWhere((c) => c.startsWith('add')),
        contains('root=/movies-4k'),
      );
      expect(prefs.values['radarr.srv1.default_root_folder'], '/movies-4k');
    });

    testWidgets('empty, idle, failure and add failure', (tester) async {
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          FakeRadarrApi(),
          const AddMovieScreen(initialTerm: 'zz'),
        ),
        variants: _both,
        verify: (v) async {
          if (_en(v)) expect(find.text('No movies found'), findsOneWidget);
          await expectAccessible(tester);
        },
      );
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, FakeRadarrApi(), const AddMovieScreen()),
        variants: _both,
        verify: (v) => expectAccessible(tester),
      );
    });

    for (final c in ErrorCategory.values) {
      testWidgets('lookup error ${c.code}', (tester) async {
        final a = FakeRadarrApi()..lookupResult = Result.err(AppError(c));
        await pumpMatrix(
          tester,
          (v) => radarrApp(v, a, const AddMovieScreen(initialTerm: 'x')),
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      });
    }

    testWidgets('add failure keeps the sheet open with the reason', (
      tester,
    ) async {
      final a = api()
        ..addResult = const Result.err(AppError(ErrorCategory.serverError));
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, a, const AddMovieScreen(initialTerm: 'movie')),
        variants: phone,
      );
      await tester.tap(find.text('Plain Movie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add and search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not add the movie'), findsOneWidget);
    });

    testWidgets('options sheet is accessible at the stress sizes', (
      tester,
    ) async {
      final a = api();
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, a, const AddMovieScreen(initialTerm: 'movie')),
        variants: stress,
        verify: (v) async {
          await tester.tap(find.text('New Movie'));
          await tester.pumpAndSettle();
          await expectAccessible(tester);
        },
      );
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
