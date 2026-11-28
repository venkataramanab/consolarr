// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/sonarr/application/library_providers.dart';
import 'package:consolarr/features/sonarr/application/library_query.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/sonarr_prefs_store.dart';
import 'package:consolarr/features/sonarr/presentation/series_views.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'library_harness.dart';
import 'support.dart';

/// Prefs whose reads wait for [gate]: the saved default arrives late.
class _SlowPrefs extends MemorySonarrPrefsStore {
  _SlowPrefs(this.gate);
  final Future<void> gate;

  @override
  Future<String?> read(String serverId, String name) async {
    await gate;
    return super.read(serverId, name);
  }
}

final _variant = harnessMatrix(
  sizes: const [Size(360, 800)],
  textScales: const [1],
  locales: const [Locale('en')],
  brightnesses: const [Brightness.dark],
).single;

String _savedTitleDescending() =>
    encodeSort(SeriesSortKey.title, ascending: false);

void main() {
  testWidgets('the first list frame waits for the saved default: no re-sort '
      'on screen', (tester) async {
    final gate = Completer<void>();
    final prefs = _SlowPrefs(gate.future);
    // Written straight into the map: the read below is what is slow.
    prefs.values[DriftSonarrPrefsStore.keyFor('srv1', 'library.sort')] =
        _savedTitleDescending();
    final notifier = FakeLibraryNotifier(dataState(fakeSeriesList(3)));
    applyVariantView(tester, _variant);
    await tester.pumpWidget(
      libraryApp(
        _variant,
        notifier: notifier,
        prefs: prefs,
        mode: LibraryViewMode.list,
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      // While the saved default is unread no row is on screen at all, so a
      // default-ordered list can never flash before the saved order.
      expect(find.textContaining('Example Show'), findsNothing, reason: '$i');
    }
    expect(find.byType(SeriesSkeleton), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SeriesSkeleton), findsNothing);
    final dy = [
      for (final i in [1, 2, 3])
        tester.getTopLeft(find.text('Example Show $i')).dy,
    ];
    // Saved: title, descending: 3 above 2 above 1.
    expect(dy[2], lessThan(dy[1]));
    expect(dy[1], lessThan(dy[0]));
  });

  group('restoring the saved default', () {
    ProviderContainer containerWith(_SlowPrefs prefs) {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...sonarrTestOverrides(ScriptedSonarrApi(), prefs: prefs),
          seriesLibraryProvider.overrideWith(
            () => FakeLibraryNotifier(dataState(fakeSeriesList(3))),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test(
      'the query is not restored until the prefs are read, then it is',
      () async {
        final gate = Completer<void>();
        final prefs = _SlowPrefs(gate.future);
        prefs.values[DriftSonarrPrefsStore.keyFor('srv1', 'library.sort')] =
            _savedTitleDescending();
        final c = containerWith(prefs);
        c.listen(libraryQueryProvider, (_, _) {});
        await c.read(sonarrSessionProvider.future);
        await settle();
        expect(c.read(libraryQueryProvider).restored, isFalse);
        gate.complete();
        await settle();
        final q = c.read(libraryQueryProvider);
        expect(q.restored, isTrue);
        expect(q.sortKey, SeriesSortKey.title);
        expect(q.ascending, isFalse);
      },
    );

    test('nothing saved: restored as soon as the read is done', () async {
      final c = containerWith(_SlowPrefs(Future<void>.value()));
      c.listen(libraryQueryProvider, (_, _) {});
      await c.read(sonarrSessionProvider.future);
      await settle();
      final q = c.read(libraryQueryProvider);
      expect(q.restored, isTrue);
      expect(q.sortKey, SeriesSortKey.added);
    });

    test(
      'a sort picked before the restore finished is not overwritten',
      () async {
        final gate = Completer<void>();
        final prefs = _SlowPrefs(gate.future);
        prefs.values[DriftSonarrPrefsStore.keyFor('srv1', 'library.sort')] =
            _savedTitleDescending();
        final c = containerWith(prefs);
        c.listen(libraryQueryProvider, (_, _) {});
        await c.read(sonarrSessionProvider.future);
        await settle();
        await c
            .read(libraryQueryProvider.notifier)
            .applySort(SeriesSortKey.year, ascending: true);
        gate.complete();
        await settle();
        final q = c.read(libraryQueryProvider);
        expect(q.restored, isTrue);
        expect(
          q.sortKey,
          SeriesSortKey.year,
          reason: 'the person\'s pick wins',
        );
        expect(q.ascending, isTrue);
      },
    );
  });
}
