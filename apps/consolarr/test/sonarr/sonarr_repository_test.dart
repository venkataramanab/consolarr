// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/data/sonarr_repository.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late AppDatabase db;
  late DriftPayloadCache cache;
  late FakeSonarrApi api;
  var now = DateTime.utc(2026, 5, 1, 12);
  late SonarrRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    cache = DriftPayloadCache(db);
    api = FakeSonarrApi();
    now = DateTime.utc(2026, 5, 1, 12);
    repo = SonarrRepository(
      api: api,
      cache: cache,
      serverId: 'srv1',
      clock: () => now,
    );
  });
  tearDown(() => db.close());

  test('success returns the list and writes it to the cache', () async {
    api.seriesResult = Result.ok(fakeSeriesList(3));
    final snap = (await repo.load()).valueOrNull!;
    expect(snap.series, hasLength(3));
    expect(snap.fetchedAt, now);
    expect(snap.offlineError, isNull);
    final hit = await cache.read('srv1', SonarrRepository.cacheKey);
    expect(hit, isNotNull);
    expect(hit!.fetchedAt.toUtc(), now);
  });

  test(
    'network failure with a cache returns cached data and the error',
    () async {
      api.seriesResult = Result.ok(fakeSeriesList(2));
      await repo.load();
      now = now.add(const Duration(hours: 3));
      api.seriesResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
      final snap = (await repo.load()).valueOrNull!;
      expect(snap.series.map((s) => s.id), [1, 2]);
      expect(snap.offlineError?.category, ErrorCategory.networkUnreachable);
      // Age is that of the cached copy, not of the failed attempt.
      expect(snap.fetchedAt, DateTime.utc(2026, 5, 1, 12));
    },
  );

  test('failure without a cache is an error', () async {
    api.seriesResult = const Result.err(AppError(ErrorCategory.timeout));
    final r = await repo.load();
    expect(r.errorOrNull?.category, ErrorCategory.timeout);
  });

  test('auth failure never falls back to the cache', () async {
    api.seriesResult = Result.ok(fakeSeriesList(1));
    await repo.load();
    api.seriesResult = const Result.err(AppError(ErrorCategory.authFailed));
    final r = await repo.load();
    expect(r.errorOrNull?.category, ErrorCategory.authFailed);
  });

  test('not_found on a legacy server becomes unsupported_version', () async {
    api.seriesResult = const Result.err(AppError(ErrorCategory.notFound));
    api.statusResult = const Result.err(
      AppError(ErrorCategory.unsupportedVersion),
    );
    final r = await repo.load();
    expect(r.errorOrNull?.category, ErrorCategory.unsupportedVersion);
    expect(api.statusCalls, 1);
  });

  test('not_found stays not_found when the version is fine', () async {
    api.seriesResult = const Result.err(AppError(ErrorCategory.notFound));
    final r = await repo.load();
    expect(r.errorOrNull?.category, ErrorCategory.notFound);
  });

  test('a corrupt cache entry is ignored, valid items are kept', () async {
    await cache.write(
      'srv1',
      SonarrRepository.cacheKey,
      '[{"id":1,"title":"Example Show 1"},{"id":"x"},42]',
      now,
    );
    api.seriesResult = const Result.err(AppError(ErrorCategory.timeout));
    final snap = (await repo.load()).valueOrNull!;
    expect(snap.series.map((s) => s.id), [1]);
    await cache.write('srv1', SonarrRepository.cacheKey, 'not json', now);
    expect((await repo.load()).errorOrNull?.category, ErrorCategory.timeout);
  });

  test('a cache write failure does not fail the load', () async {
    api.seriesResult = Result.ok(fakeSeriesList(1));
    await db.close();
    final snap = (await repo.load()).valueOrNull;
    expect(snap?.series, hasLength(1));
    db = AppDatabase.memory();
  });

  test('cached() reads without touching the network', () async {
    api.seriesResult = Result.ok(fakeSeriesList(2));
    await repo.load();
    final calls = api.seriesCalls;
    expect((await repo.cached())?.series, hasLength(2));
    expect(api.seriesCalls, calls);
  });
}
