// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/data/calendar_repository.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final start = DateTime.utc(2026, 5);
  final end = DateTime.utc(2026, 5, 15);
  final at = DateTime.utc(2026, 5, 1, 12);

  late ScriptedSonarrApi api;
  late MemoryPayloadCache cache;
  late CalendarRepository repo;

  setUp(() {
    api = ScriptedSonarrApi();
    cache = MemoryPayloadCache();
    repo = CalendarRepository(
      api: api,
      cache: cache,
      serverId: 'srv1',
      clock: () => at,
    );
  });

  Future<Result<CalendarSnapshot>> load({
    DateTime? s,
    DateTime? e,
    bool unmonitored = false,
  }) => repo.load(
    start: s ?? start,
    end: e ?? end,
    includeUnmonitored: unmonitored,
  );

  test('a live load is returned and cached with its age', () async {
    api.calendarResult = Result.ok([
      fakeEpisode(1, airs: DateTime.utc(2026, 5, 3)),
    ]);
    final snapshot = (await load()).valueOrNull!;
    expect(snapshot.episodes, hasLength(1));
    expect(snapshot.isOffline, isFalse);
    expect(cache.entries['srv1/sonarr.calendar']!.fetchedAt, at);
  });

  test('a reachability failure falls back to the covered cache', () async {
    api.calendarResult = Result.ok([
      fakeEpisode(1, airs: DateTime.utc(2026, 5, 3)),
      fakeEpisode(2, airs: DateTime.utc(2026, 5, 10), monitored: false),
    ]);
    await load(unmonitored: true);
    api.calendarResult = const Result.err(
      AppError(ErrorCategory.networkUnreachable),
    );
    // Sub-window, monitored only: the unmonitored episode is filtered out.
    final snapshot = (await load(
      s: DateTime.utc(2026, 5, 2),
      e: DateTime.utc(2026, 5, 12),
    )).valueOrNull!;
    expect(snapshot.isOffline, isTrue);
    expect(snapshot.episodes.map((e) => e.id), [1]);
  });

  test(
    'no fallback when the cached window does not cover the request',
    () async {
      api.calendarResult = Result.ok([fakeEpisode(1)]);
      await load();
      api.calendarResult = const Result.err(AppError(ErrorCategory.timeout));
      final result = await load(e: DateTime.utc(2026, 6));
      expect(result.errorOrNull?.category, ErrorCategory.timeout);
    },
  );

  test(
    'cached monitored-only window cannot answer an unmonitored request',
    () async {
      api.calendarResult = Result.ok([fakeEpisode(1)]);
      await load();
      api.calendarResult = const Result.err(AppError(ErrorCategory.timeout));
      expect((await load(unmonitored: true)).isOk, isFalse);
    },
  );

  for (final category in [
    ErrorCategory.authFailed,
    ErrorCategory.unsupportedVersion,
    ErrorCategory.tlsUntrusted,
    ErrorCategory.tlsPinMismatch,
    ErrorCategory.tlsExpired,
  ]) {
    test('${category.code} is never hidden behind cached data', () async {
      api.calendarResult = Result.ok([fakeEpisode(1)]);
      await load();
      api.calendarResult = Result.err(AppError(category));
      final result = await load();
      expect(result.errorOrNull?.category, category);
    });
  }

  test('a damaged cache entry is ignored', () async {
    await cache.write('srv1', 'sonarr.calendar', 'not json', at);
    api.calendarResult = const Result.err(AppError(ErrorCategory.timeout));
    expect((await load()).isOk, isFalse);
  });
}
