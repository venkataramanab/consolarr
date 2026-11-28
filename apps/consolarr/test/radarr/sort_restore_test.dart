// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/data/radarr_prefs.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/presentation/library_page.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

/// Prefs whose reads wait for [gate]: the saved default arrives late.
class _SlowPrefs extends MemoryPrefs {
  _SlowPrefs(this.gate);
  final Future<void> gate;

  @override
  Future<String?> read(String key) async {
    await gate;
    return super.read(key);
  }
}

const _pad = EdgeInsets.fromLTRB(16, 60, 16, 88);

String _titleDescending() => jsonEncode({'key': 'title', 'asc': false});

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  testWidgets('the first list frame waits for the saved default: no re-sort '
      'on screen', (tester) async {
    final gate = Completer<void>();
    final prefs = _SlowPrefs(gate.future)
      ..values[RadarrPrefKeys.librarySort('srv1')] = _titleDescending();
    final api = FakeRadarrApi(moviesResult: Result.ok(fakeMovies(3)));
    final variant = phone.single;
    applyVariantView(tester, variant);
    await tester.pumpWidget(
      radarrApp(variant, api, const LibraryPage(padding: _pad), prefs: prefs),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // The unsorted (default-ordered) rows never appear before the saved
      // order is known.
      expect(find.textContaining('Example Movie'), findsNothing, reason: '$i');
    }
    expect(find.byType(MovieSkeleton), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MovieSkeleton), findsNothing);
    // The saved order: title, descending. The rows are in a grid or a list:
    // compare reading order (row, then column).
    final spots = [
      for (final i in [1, 2, 3])
        tester.getTopLeft(find.text('Example Movie $i')),
    ];
    bool before(Offset a, Offset b) =>
        a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx);
    expect(before(spots[2], spots[1]), isTrue);
    expect(before(spots[1], spots[0]), isTrue);
  });

  group('restoring the saved default', () {
    ProviderContainer containerWith(MemoryPrefs prefs) {
      final c = ProviderContainer(
        overrides: radarrOverrides(FakeRadarrApi(), prefs: prefs),
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'the query is not restored until the prefs are read, then it is',
      () async {
        final gate = Completer<void>();
        final prefs = _SlowPrefs(gate.future)
          ..values[RadarrPrefKeys.librarySort('srv1')] = _titleDescending();
        final c = containerWith(prefs);
        await c.read(radarrContextProvider.future);
        c.listen(libraryQueryProvider, (_, _) {});
        await _settle();
        expect(c.read(libraryQueryProvider).restored, isFalse);
        gate.complete();
        await _settle();
        final q = c.read(libraryQueryProvider);
        expect(q.restored, isTrue);
        expect(q.sort, MovieSortKey.title);
        expect(q.ascending, isFalse);
      },
    );

    test('nothing saved: restored as soon as the read is done', () async {
      final c = containerWith(_SlowPrefs(Future<void>.value()));
      await c.read(radarrContextProvider.future);
      c.listen(libraryQueryProvider, (_, _) {});
      await _settle();
      final q = c.read(libraryQueryProvider);
      expect(q.restored, isTrue);
      expect(q.sort, MovieSortKey.added);
    });

    test(
      'a sort picked before the restore finished is not overwritten',
      () async {
        final gate = Completer<void>();
        final prefs = _SlowPrefs(gate.future)
          ..values[RadarrPrefKeys.librarySort('srv1')] = _titleDescending();
        final c = containerWith(prefs);
        await c.read(radarrContextProvider.future);
        c.listen(libraryQueryProvider, (_, _) {});
        await _settle();
        await c
            .read(libraryQueryProvider.notifier)
            .setSort(MovieSortKey.year, ascending: true);
        gate.complete();
        await _settle();
        final q = c.read(libraryQueryProvider);
        expect(q.restored, isTrue);
        expect(q.sort, MovieSortKey.year, reason: 'the person\'s pick wins');
        expect(q.ascending, isTrue);
      },
    );
  });
}
