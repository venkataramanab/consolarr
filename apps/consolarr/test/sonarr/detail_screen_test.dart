// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/presentation/detail/detail_hero.dart';
import 'package:consolarr/features/sonarr/presentation/detail/detail_seasons.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'detail_harness.dart';
import 'fakes.dart';

/// 320x568 (the smallest phone) and a large phone x en, en_XA, ar x scale
/// 1.0 and 2.0, dark.
final _variants = harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  brightnesses: const [Brightness.dark],
);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<AppLocalizations> _l10n(HarnessVariant v) =>
    AppLocalizations.delegate.load(v.locale);

void main() {
  Future<void> expectStates(
    WidgetTester tester,
    ScriptedSonarrApi Function() api,
    Future<void> Function(HarnessVariant v) verify, {
    int seriesId = 1,
  }) => pumpMatrix(
    tester,
    (v) => detailApp(v, api: api(), seriesId: seriesId),
    variants: _variants,
    verify: (v) async {
      await verify(v);
      await expectAccessible(tester);
    },
  );

  testWidgets('data: hero, facts, links and the newest season expanded', (
    tester,
  ) async {
    await expectStates(tester, detailApi, (v) async {
      expect(find.text('Example Show 1'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('season-2')));
      await reveal(tester, find.textContaining('Example Episode 4'));
    });
  });

  test('seasons are listed newest first', () {
    final grouped = groupBySeason([fakeEpisode(1), fakeEpisode(2, season: 3)]);
    final merged = mergedSeasons(const [SonarrSeason(number: 1)], grouped);
    expect([for (final s in merged) s.number], [3, 1]);
  });

  testWidgets('absent sections are omitted', (tester) async {
    final api = detailApi(overview: null);
    await pumpMatrix(
      tester,
      (v) => detailApp(v, api: api),
      variants: [_variants.first],
    );
    expect(find.text('An example overview.'), findsNothing);
  });

  testWidgets('loading shows the skeleton, never the previous data', (
    tester,
  ) async {
    final gate = Completer<void>();
    await expectStates(
      tester,
      () {
        return detailApi()..hook = (_) => gate.future;
      },
      (v) async {
        expect(find.text('Example Show 1'), findsNothing);
        expect(
          find.bySemanticsLabel((await _l10n(v)).sonarrDetailLoading),
          findsWidgets,
        );
      },
    );
  });

  testWidgets('series that no longer exists', (tester) async {
    await expectStates(
      tester,
      () =>
          ScriptedSonarrApi()
            ..detailResult = const Result.err(AppError(ErrorCategory.notFound)),
      (v) async {
        final l = await _l10n(v);
        expect(find.text(l.sonarrDetailGoneHeadline), findsOneWidget);
        expect(find.text(l.sonarrDetailGoneAction), findsOneWidget);
      },
    );
  });

  for (final c in [
    ErrorCategory.authFailed,
    ErrorCategory.networkUnreachable,
    ErrorCategory.unsupportedVersion,
    ErrorCategory.tlsUntrusted,
  ]) {
    testWidgets('error ${c.code} with retry and no stale data', (tester) async {
      await pumpMatrix(
        tester,
        (v) => detailApp(
          v,
          api: ScriptedSonarrApi()..detailResult = Result.err(AppError(c)),
        ),
        variants: [_variants.first],
        verify: (v) async {
          expect(find.text((await _l10n(v)).sonarrRetry), findsOneWidget);
          expect(find.text('Example Show 1'), findsNothing);
        },
      );
    });
  }

  testWidgets('offline: cached data, age banner and writes disabled', (
    tester,
  ) async {
    final cache = MemoryPayloadCache();
    // Fill the cache with a live load first.
    final live = detailApi();
    await pumpMatrix(
      tester,
      (v) => detailApp(v, api: live, cache: cache),
      variants: [_variants.first],
    );
    expect(cache.entries, isNotEmpty);
    // Drop the first app so the next one starts with fresh providers.
    await tester.pumpWidget(const SizedBox());

    final offline = ScriptedSonarrApi()
      ..detailResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
    await pumpMatrix(
      tester,
      (v) => detailApp(
        v,
        api: offline,
        cache: cache,
        now: DateTime.utc(2026, 5, 1, 15),
      ),
      variants: _variants,
      verify: (v) async {
        final l = await _l10n(v);
        expect(find.text(l.sonarrDetailOfflineMessage), findsOneWidget);
        if (v.locale == const Locale('en')) {
          expect(find.text('Updated 3 hours ago'), findsOneWidget);
        }
        // Edit is disabled and explains why.
        final edit = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.edit_outlined),
        );
        expect(edit.onPressed, isNull);
        for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
          expect(s.onChanged, isNull);
        }
        await expectAccessible(tester);
      },
    );
  });

  testWidgets('offline without a cache is an error, not an empty screen', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      (v) => detailApp(
        v,
        api: ScriptedSonarrApi()
          ..detailResult = const Result.err(
            AppError(ErrorCategory.networkUnreachable),
          ),
      ),
      variants: [_variants.first],
      verify: (v) async =>
          expect(find.text((await _l10n(v)).sonarrRetry), findsOneWidget),
    );
  });

  testWidgets('episode list failing keeps the series and offers a retry', (
    tester,
  ) async {
    await expectStates(
      tester,
      () => detailApi()
        ..episodesResult = const Result.err(AppError(ErrorCategory.timeout)),
      (v) async {
        expect(find.text('Example Show 1'), findsOneWidget);
        await reveal(
          tester,
          find.text((await _l10n(v)).sonarrDetailEpisodesErrorTitle),
        );
      },
    );
  });

  testWidgets('a season without episodes says so', (tester) async {
    final api = detailApi(episodes: 0);
    // Season 2 is expanded and empty.
    await pumpMatrix(
      tester,
      (v) => detailApp(v, api: api),
      variants: [_variants.first],
      verify: (v) async =>
          reveal(tester, find.text((await _l10n(v)).sonarrDetailNoEpisodes)),
    );
  });

  testWidgets('episode status is icon plus text', (tester) async {
    final api = detailApi()
      ..queueResult = Result.ok([fakeQueueItem(2, seriesId: 1)]);
    await pumpMatrix(
      tester,
      (v) => detailApp(v, api: api),
      variants: [_variants.first],
    );
    // Season 2 is expanded: episode 4 is in the future; open season 1 too.
    await reveal(tester, find.byKey(const ValueKey('season-1')));
    await tester.tap(find.byKey(const ValueKey('season-1')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Downloaded'));
    await reveal(tester, find.text('Downloading'));
    await reveal(tester, find.text('Not aired yet'));
  });

  testWidgets('artwork is decoded at display size', (tester) async {
    await pumpMatrix(
      tester,
      (v) => detailApp(v, api: detailApi(), artwork: MemoryArtwork()),
      variants: [_variants.first],
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    for (final image in images) {
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, isNotNull);
    }
    final poster = images.last.image as ResizeImage;
    expect(poster.width, lessThanOrEqualTo((heroPosterWidth * 4).round()));
  });

  testWidgets('10,000 episodes build lazily', (tester) async {
    final api = detailApi()
      ..episodesResult = Result.ok([
        for (var i = 1; i <= 10000; i++) fakeEpisode(i, season: 2, number: i),
      ]);
    await pumpMatrix(
      tester,
      (v) => detailApp(v, api: api),
      variants: [_variants.first],
    );
    // Only a screenful of rows exists.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Example Episode'), findsWidgets);
    expect(
      tester.widgetList(find.textContaining('Example Episode')).length,
      lessThan(40),
    );
  });
}
