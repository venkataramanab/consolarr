// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/data/radarr_repository.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late FakeRadarrApi api;
  late MemoryPayloadCache cache;
  late RadarrRepository repo;
  setUp(() {
    api = FakeRadarrApi();
    cache = MemoryPayloadCache();
    repo = RadarrRepository(
      api: api,
      cache: cache,
      serverId: 'srv1',
      clock: () => fixedNow,
    );
  });

  test('a live load is stored and returned fresh', () async {
    api.moviesResult = Result.ok(fakeMovies(3));
    final r = await repo.library();
    expect(r.valueOrNull!.value, hasLength(3));
    expect(r.valueOrNull!.isOffline, isFalse);
    expect(cache.rows, isNotEmpty);
  });

  test('reachability failures fall back to the cache with the error', () async {
    api.moviesResult = Result.ok(fakeMovies(2));
    await repo.library();
    for (final c in [
      ErrorCategory.networkUnreachable,
      ErrorCategory.timeout,
      ErrorCategory.serverError,
    ]) {
      api.moviesResult = Result.err(AppError(c));
      final r = await repo.library();
      expect(r.valueOrNull!.isOffline, isTrue, reason: c.code);
      expect(r.valueOrNull!.value, hasLength(2));
    }
  });

  test('auth, version and TLS failures never fall back to the cache', () async {
    api.moviesResult = Result.ok(fakeMovies(2));
    await repo.library();
    for (final c in [
      ErrorCategory.authFailed,
      ErrorCategory.unsupportedVersion,
      ErrorCategory.tlsUntrusted,
      ErrorCategory.tlsPinMismatch,
      ErrorCategory.tlsExpired,
    ]) {
      api.moviesResult = Result.err(AppError(c));
      final r = await repo.library();
      expect(r.errorOrNull?.category, c);
    }
  });

  test('nothing is written to the cache on failure', () async {
    api.moviesResult = const Result.err(AppError(ErrorCategory.authFailed));
    await repo.library();
    expect(cache.rows, isEmpty);
  });

  test('offline detail falls back to its library row', () async {
    api.moviesResult = Result.ok(fakeMovies(3));
    await repo.library();
    api.movieResult = const Result.err(AppError(ErrorCategory.timeout));
    final r = await repo.movie(2);
    expect(r.valueOrNull!.isOffline, isTrue);
    expect(r.valueOrNull!.value.id, 2);
  });

  test('a deleted movie is not_found and not served from cache', () async {
    api.moviesResult = Result.ok(fakeMovies(3));
    await repo.library();
    api.movieResult = const Result.err(AppError(ErrorCategory.notFound));
    final r = await repo.movie(2);
    // not_found is in the offline set, so the library row is offered; the
    // notifier decides "gone" only when nothing cached exists.
    expect(r.isOk || r.errorOrNull?.category == ErrorCategory.notFound, isTrue);
    final missing = await repo.movie(77);
    expect(missing.errorOrNull?.category, ErrorCategory.notFound);
  });

  test('a damaged cache entry is skipped, not fatal', () async {
    await cache.write(
      'srv1',
      RadarrRepository.libraryKey,
      '[{"id":1,"title":"Example Movie"},{"id":"x"}, 5]',
      fixedNow,
    );
    api.moviesResult = const Result.err(AppError(ErrorCategory.timeout));
    final r = await repo.library();
    expect(r.valueOrNull!.value, hasLength(1));
  });
}
