// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/detail_repository.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detail_harness.dart';
import 'fakes.dart';

void main() {
  ProviderContainer container(
    ScriptedSonarrApi api, {
    MemoryPayloadCache? cache,
  }) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: sonarrTestOverrides(api, cache: cache),
    );
    addTearDown(c.dispose);
    c.listen(seriesDetailProvider(1), (_, _) {});
    return c;
  }

  Future<DetailData> load(ProviderContainer c) async =>
      await c.read(seriesDetailProvider(1).future) as DetailData;

  DetailData current(ProviderContainer c) =>
      c.read(seriesDetailProvider(1)).value! as DetailData;

  group('repository', () {
    test('caches the last good copy and falls back to it offline', () async {
      final cache = MemoryPayloadCache();
      final api = detailApi();
      final live = DetailRepository(
        api: api,
        cache: cache,
        serverId: 'srv1',
        clock: () => DateTime.utc(2026, 5, 1),
      );
      final first = (await live.load(1)).valueOrNull!;
      expect(first.episodes, hasLength(4));
      expect(first.isOffline, isFalse);

      api.detailResult = const Result.err(AppError(ErrorCategory.timeout));
      final offline = (await live.load(1)).valueOrNull!;
      expect(offline.isOffline, isTrue);
      expect(offline.episodes, hasLength(4));
      expect(offline.fetchedAt, DateTime.utc(2026, 5, 1));
    });

    for (final c in [
      ErrorCategory.authFailed,
      ErrorCategory.unsupportedVersion,
      ErrorCategory.tlsUntrusted,
      ErrorCategory.tlsPinMismatch,
      ErrorCategory.notFound,
    ]) {
      test('never falls back to the cache after ${c.code}', () async {
        final cache = MemoryPayloadCache();
        final api = detailApi();
        final repo = DetailRepository(
          api: api,
          cache: cache,
          serverId: 'srv1',
          clock: () => DateTime.utc(2026, 5, 1),
        );
        await repo.load(1);
        api.detailResult = Result.err(AppError(c));
        expect((await repo.load(1)).errorOrNull?.category, c);
      });
    }

    test('an episode failure keeps the series and does not cache', () async {
      final cache = MemoryPayloadCache();
      final api = detailApi()
        ..episodesResult = const Result.err(AppError(ErrorCategory.timeout));
      final repo = DetailRepository(
        api: api,
        cache: cache,
        serverId: 'srv1',
        clock: DateTime.now,
      );
      final snap = (await repo.load(1)).valueOrNull!;
      expect(snap.episodesError?.category, ErrorCategory.timeout);
      expect(cache.entries, isEmpty);
    });

    test('a damaged cache is ignored', () async {
      final cache = MemoryPayloadCache()
        ..entries['srv1/sonarr.series.1'] = CachedPayload(
          json: '{broken',
          fetchedAt: DateTime.utc(2026),
        );
      final repo = DetailRepository(
        api: ScriptedSonarrApi(),
        cache: cache,
        serverId: 'srv1',
        clock: DateTime.now,
      );
      expect(await repo.cached(1), isNull);
    });
  });

  group('notifier', () {
    test('loads the series, marks queued episodes as downloading', () async {
      final api = detailApi()
        ..queueResult = Result.ok([fakeQueueItem(2, seriesId: 1)]);
      final data = await load(container(api));
      expect(data.snapshot.downloading, {2});
    });

    test('a missing series is the gone state, not an error', () async {
      final api = ScriptedSonarrApi()
        ..detailResult = const Result.err(AppError(ErrorCategory.notFound));
      final c = container(api);
      expect(await c.read(seriesDetailProvider(1).future), isA<DetailGone>());
    });

    test('an invalid id is gone without a request', () async {
      final api = ScriptedSonarrApi();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: sonarrTestOverrides(api),
      );
      addTearDown(c.dispose);
      c.listen(seriesDetailProvider(-1), (_, _) {});
      expect(await c.read(seriesDetailProvider(-1).future), isA<DetailGone>());
      expect(api.count('seriesDetail'), 0);
    });

    test('auth failure is an error, not hidden behind data', () async {
      final api = ScriptedSonarrApi()
        ..detailResult = const Result.err(AppError(ErrorCategory.authFailed));
      final c = container(api);
      await expectLater(
        c.read(seriesDetailProvider(1).future),
        throwsA(isA<AppError>()),
      );
    });

    test('episode toggle is optimistic and saved', () async {
      final api = detailApi();
      final c = container(api);
      await load(c);
      final gate = Completer<void>();
      api.hook = (name) =>
          name == 'setEpisodesMonitored' ? gate.future : Future<void>.value();
      final f = c
          .read(seriesDetailProvider(1).notifier)
          .setEpisodeMonitored(2, monitored: false);
      await Future<void>.delayed(Duration.zero);
      expect(current(c).pendingEpisodes, {2});
      expect(
        current(c).snapshot.episodes.firstWhere((e) => e.id == 2).monitored,
        isFalse,
      );
      gate.complete();
      await f;
      expect(current(c).pendingEpisodes, isEmpty);
      expect(current(c).failedEpisodes, isEmpty);
      final (ids, monitored) = api.sent.last! as (List<int>, bool);
      expect(ids, [2]);
      expect(monitored, isFalse);
    });

    test('a failed toggle reverts, shows the row error and retries', () async {
      final api = detailApi()
        ..monitorResult = const Result.err(AppError(ErrorCategory.timeout));
      final c = container(api);
      await load(c);
      final notifier = c.read(seriesDetailProvider(1).notifier);
      await notifier.setEpisodeMonitored(2, monitored: false);
      expect(current(c).failedEpisodes, {2: false});
      expect(
        current(c).snapshot.episodes.firstWhere((e) => e.id == 2).monitored,
        isTrue,
      );
      api.monitorResult = const Result.ok(null);
      await notifier.setEpisodeMonitored(2, monitored: false);
      expect(current(c).failedEpisodes, isEmpty);
      expect(
        current(c).snapshot.episodes.firstWhere((e) => e.id == 2).monitored,
        isFalse,
      );
    });

    test(
      'season toggle updates the series resource then the episodes',
      () async {
        final api = detailApi();
        api.updateResult = Result.ok(fakeDetail(1));
        final c = container(api);
        await load(c);
        final before = api.count('episodes');
        await c
            .read(seriesDetailProvider(1).notifier)
            .setSeasonMonitored(1, monitored: false);
        final payload = api.sent.whereType<Map<String, Object?>>().last;
        final seasons = (payload['seasons']! as List)
            .cast<Map<String, Object?>>();
        expect(
          seasons.firstWhere((s) => s['seasonNumber'] == 1)['monitored'],
          isFalse,
        );
        expect(api.count('episodes'), before + 1);
        expect(current(c).pendingSeasons, isEmpty);
      },
    );

    test('writes are ignored while offline', () async {
      final cache = MemoryPayloadCache();
      final api = detailApi();
      var c = container(api, cache: cache);
      await load(c);
      c.dispose();
      api.detailResult = const Result.err(AppError(ErrorCategory.timeout));
      c = container(api, cache: cache);
      final data = await load(c);
      expect(data.isOffline, isTrue);
      final notifier = c.read(seriesDetailProvider(1).notifier);
      await notifier.setEpisodeMonitored(2, monitored: false);
      await notifier.setSeasonMonitored(1, monitored: false);
      final error = await notifier.saveEdit(
        monitored: false,
        qualityProfileId: 1,
        tags: const [],
      );
      expect(error, isNotNull);
      expect(api.count('setEpisodesMonitored'), 0);
      expect(api.count('updateSeries'), 0);
    });

    test(
      'saveEdit sends only the edited fields over the raw payload',
      () async {
        final api = detailApi();
        final c = container(api);
        await load(c);
        api.updateResult = Result.ok(fakeDetail(1, monitored: false));
        final error = await c
            .read(seriesDetailProvider(1).notifier)
            .saveEdit(monitored: false, qualityProfileId: 2, tags: const [5]);
        expect(error, isNull);
        final sent = api.sent.whereType<Map<String, Object?>>().last;
        expect(sent['monitored'], isFalse);
        expect(sent['qualityProfileId'], 2);
        expect(sent['tags'], [5]);
        // Everything else is sent back unchanged (no path or type edit).
        expect(sent['path'], '/media/tv/Example Show 1');
        expect(sent['seriesType'], 'standard');
        expect(current(c).snapshot.detail.summary.monitored, isFalse);
      },
    );

    test('saveEdit failure is returned for a retry', () async {
      final api = detailApi();
      final c = container(api);
      await load(c);
      api.updateResult = const Result.err(AppError(ErrorCategory.serverError));
      final error = await c
          .read(seriesDetailProvider(1).notifier)
          .saveEdit(monitored: false, qualityProfileId: 1, tags: const []);
      expect(error?.category, ErrorCategory.serverError);
    });

    test('no server', () async {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sonarrSessionProvider.overrideWith((ref) async => null),
          clockProvider.overrideWithValue(DateTime.now),
        ],
      );
      addTearDown(c.dispose);
      c.listen(seriesDetailProvider(1), (_, _) {});
      expect(
        await c.read(seriesDetailProvider(1).future),
        isA<DetailNoServer>(),
      );
    });
  });

  test('external links: only fixed https hosts built from identifiers', () {
    final detail = SonarrSeriesDetail.fromJson({
      'id': 1,
      'title': 'Example Show',
      'imdbId': 'tt0000001',
      'tvdbId': 5,
      'tmdbId': 6,
      'tvMazeId': 7,
    });
    for (final link in detail.externalLinks) {
      expect(isOpenableExternalUri(link.uri), isTrue);
      expect(link.uri.scheme, 'https');
    }
    final bad = SonarrSeriesDetail.fromJson({
      'id': 1,
      'title': 'x',
      'imdbId': 'javascript:alert(1)',
    });
    expect(bad.externalLinks, isEmpty);
    expect(isOpenableExternalUri(Uri.parse('javascript:alert(1)')), isFalse);
    expect(isOpenableExternalUri(Uri.parse('intent://x#Intent;end')), isFalse);
    expect(isOpenableExternalUri(Uri.parse('https://u:p@x.example/')), isFalse);
  });

  group('writes that finish after a refresh failed', () {
    // The refresh that lands meanwhile either errors (auth) or finds the
    // series gone; neither leaves data for the finished write to update.
    Future<void> failRefresh(
      ProviderContainer c,
      ScriptedSonarrApi api, {
      ErrorCategory category = ErrorCategory.authFailed,
    }) async {
      api.detailResult = Result.err(AppError(category));
      await c.read(seriesDetailProvider(1).notifier).refresh();
      final s = c.read(seriesDetailProvider(1));
      expect(s.hasError || s.value is DetailGone, isTrue);
    }

    bool unchanged(ProviderContainer c) {
      final s = c.read(seriesDetailProvider(1));
      return s.hasError || s.value is DetailGone;
    }

    for (final category in [ErrorCategory.authFailed, ErrorCategory.notFound]) {
      test('an episode toggle does not throw (${category.code})', () async {
        final gate = Completer<void>();
        final api = detailApi()
          ..hook = (n) =>
              n == 'setEpisodesMonitored' ? gate.future : Future.value();
        final c = container(api);
        await load(c);
        final toggle = c
            .read(seriesDetailProvider(1).notifier)
            .setEpisodeMonitored(2, monitored: false);
        await Future<void>.delayed(Duration.zero);
        await failRefresh(c, api, category: category);
        gate.complete();
        await toggle;
        expect(unchanged(c), isTrue);
      });

      test('a season toggle does not throw (${category.code})', () async {
        final gate = Completer<void>();
        final api = detailApi()
          ..updateResult = Result.ok(fakeDetail(1))
          ..hook = (n) => n == 'updateSeries' ? gate.future : Future.value();
        final c = container(api);
        await load(c);
        final toggle = c
            .read(seriesDetailProvider(1).notifier)
            .setSeasonMonitored(1, monitored: false);
        await Future<void>.delayed(Duration.zero);
        await failRefresh(c, api, category: category);
        gate.complete();
        await toggle;
        expect(unchanged(c), isTrue);
      });

      test('saving the edit sheet does not throw (${category.code})', () async {
        final gate = Completer<void>();
        final api = detailApi()
          ..updateResult = Result.ok(fakeDetail(1))
          ..hook = (n) => n == 'updateSeries' ? gate.future : Future.value();
        final c = container(api);
        await load(c);
        final save = c
            .read(seriesDetailProvider(1).notifier)
            .saveEdit(monitored: false, qualityProfileId: 1, tags: const []);
        await Future<void>.delayed(Duration.zero);
        await failRefresh(c, api, category: category);
        gate.complete();
        expect(await save, isNull);
      });

      test('an episode reload does not throw (${category.code})', () async {
        final gate = Completer<void>();
        final api = detailApi()
          ..hook = (n) => n == 'episodes' ? gate.future : Future.value();
        final c = container(api);
        // First load needs the episodes; open the gate for it, then close it.
        gate.complete();
        await load(c);
        final second = Completer<void>();
        api.hook = (n) => n == 'episodes' ? second.future : Future.value();
        final reload = c
            .read(seriesDetailProvider(1).notifier)
            .reloadEpisodes();
        await Future<void>.delayed(Duration.zero);
        await failRefresh(c, api, category: category);
        second.complete();
        await reload;
      });
    }
  });
}
