// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/presentation/add_movie_screen.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

bool _en(HarnessVariant v) => v.locale == const Locale('en');

final _both = [...phone, ...stress];

/// A fake whose shared lists and add call can be scripted.
class _ScriptedApi extends FakeRadarrApi {
  _ScriptedApi();

  bool profilesFail = false;
  Completer<Result<RadarrMovie>>? addGate;
  int addCalls = 0;

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() async =>
      profilesFail
      ? const Result.err(AppError(ErrorCategory.timeout))
      : super.qualityProfiles();

  @override
  Future<Result<RadarrMovie>> addMovie(AddMovieRequest request) {
    addCalls++;
    final gate = addGate;
    return gate == null ? super.addMovie(request) : gate.future;
  }
}

void main() {
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

    testWidgets('typing in quick succession sends one lookup (debounce)', (
      tester,
    ) async {
      final a = api();
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, a, const AddMovieScreen()),
        variants: phone,
      );
      final lookups = () => a.calls.where((c) => c.startsWith('lookup')).length;
      final before = lookups();
      for (final text in ['m', 'mo', 'mov', 'movi', 'movie']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Still inside the debounce window of the last keystroke.
      expect(lookups(), before);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(lookups() - before, 1);
      expect(
        a.calls.where((c) => c.startsWith('lookup')).last,
        contains('movie'),
      );
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

  group('add flow review fixes', () {
    final results = [
      RadarrMovie(
        id: 0,
        title: 'New Movie',
        sortTitle: 'new movie',
        year: 2025,
        tmdbId: 11,
      ),
    ];

    _ScriptedApi scripted() => _ScriptedApi()
      ..lookupResult = Result.ok(results)
      ..rootFoldersResult = [const ArrRootFolder(id: 1, path: '/movies')];

    Future<void> openOptions(WidgetTester tester, _ScriptedApi a) async {
      await pumpMatrix(
        tester,
        (v) => radarrApp(v, a, const AddMovieScreen(initialTerm: 'movie')),
        variants: phone,
      );
      await tester.tap(find.text('New Movie'));
      await tester.pumpAndSettle();
    }

    testWidgets('profiles failing shows an error with retry, not an empty '
        'picker, and Add stays off', (tester) async {
      final a = scripted()..profilesFail = true;
      await openOptions(tester, a);
      expect(find.text("Couldn't load the options"), findsOneWidget);
      expect(find.text('Add and search'), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);

      a.profilesFail = false;
      await tester.tap(find.text('Try again').last);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load the options"), findsNothing);
      expect(find.text('Add and search'), findsOneWidget);
    });

    testWidgets('the error state is accessible at the stress sizes', (
      tester,
    ) async {
      final a = scripted()..profilesFail = true;
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

    testWidgets('a second tap while adding sends nothing', (tester) async {
      final a = scripted()..addGate = Completer<Result<RadarrMovie>>();
      await openOptions(tester, a);
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pump();
      await tester.tap(find.text('Adding…'), warnIfMissed: false);
      await tester.pump();
      expect(a.addCalls, 1);
      a.addGate!.complete(Result.ok(fakeMovie(99)));
      await tester.pumpAndSettle();
      expect(a.addCalls, 1);
      expect(find.text('Movie added'), findsOneWidget);
    });

    testWidgets('popping the sheet while adding is safe', (tester) async {
      final a = scripted()..addGate = Completer<Result<RadarrMovie>>();
      await openOptions(tester, a);
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      a.addGate!.complete(Result.ok(fakeMovie(99)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(a.addCalls, 1);
      expect(find.text('Movie added'), findsOneWidget);
    });

    testWidgets('after a timeout the library is checked: an added movie is '
        'a success, no second request', (tester) async {
      final a = scripted()
        ..addResult = const Result.err(AppError(ErrorCategory.timeout))
        ..moviesResult = Result.ok([
          RadarrMovie(
            id: 9,
            title: 'New Movie',
            sortTitle: 'new movie',
            tmdbId: 11,
          ),
        ]);
      await openOptions(tester, a);
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pumpAndSettle();
      expect(a.addCalls, 1);
      expect(find.text('Movie added'), findsOneWidget);
    });

    testWidgets('after a timeout with the movie missing the error shows', (
      tester,
    ) async {
      final a = scripted()
        ..addResult = const Result.err(AppError(ErrorCategory.timeout));
      await openOptions(tester, a);
      await tester.ensureVisible(find.text('Add and search'));
      await tester.tap(find.text('Add and search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not add the movie'), findsOneWidget);
    });
  });
}
