// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:core/core.dart';

/// Which list the wanted tab shows (SON-20).
enum WantedScope {
  /// Missing episodes plus episodes below their quality cutoff.
  wanted,

  /// Missing episodes only.
  missing,

  /// Episodes airing in the next [WantedRepository.upcomingDays] days.
  upcoming,
}

/// One page of wanted episodes.
class WantedPage {
  const WantedPage({
    required this.episodes,
    required this.page,
    required this.hasMore,
  });

  final List<SonarrEpisode> episodes;
  final int page;
  final bool hasMore;
}

/// Reads the wanted lists. Nothing is cached: the lists are action lists and
/// only meaningful live.
class WantedRepository {
  WantedRepository({
    required SonarrApi api,
    required DateTime Function() clock,
  }) : _api = api,
       _clock = clock;

  static const pageSize = 50;
  static const upcomingDays = 14;

  final SonarrApi _api;
  final DateTime Function() _clock;

  Future<Result<WantedPage>> load(WantedScope scope, {int page = 1}) async {
    switch (scope) {
      case WantedScope.missing:
        return _kind(SonarrWantedKind.missing, page);
      case WantedScope.wanted:
        final results = await Future.wait([
          _kind(SonarrWantedKind.missing, page),
          _kind(SonarrWantedKind.cutoffUnmet, page),
        ]);
        final missing = results[0];
        final cutoff = results[1];
        final error = missing.errorOrNull;
        if (error != null) return Result.err(error);
        final m = missing.valueOrNull!;
        // Cutoff-unmet is absent on some servers: tolerate its failure.
        final c = cutoff.valueOrNull;
        final seen = {for (final e in m.episodes) e.id};
        return Result.ok(
          WantedPage(
            episodes: [
              ...m.episodes,
              if (c != null)
                for (final e in c.episodes)
                  if (!seen.contains(e.id)) e,
            ],
            page: page,
            hasMore: m.hasMore || (c?.hasMore ?? false),
          ),
        );
      case WantedScope.upcoming:
        final now = _clock();
        final start = DateTime.utc(now.year, now.month, now.day);
        final result = await _api.calendar(
          start: start,
          end: start.add(const Duration(days: upcomingDays)),
        );
        return result.when(
          ok: (items) => Result.ok(
            WantedPage(episodes: items, page: 1, hasMore: false),
          ),
          err: Result.err,
        );
    }
  }

  Future<Result<WantedPage>> _kind(SonarrWantedKind kind, int page) async {
    final result = await _api.wanted(kind, page: page, pageSize: pageSize);
    return result.when(
      ok: (p) => Result.ok(
        WantedPage(episodes: p.records, page: page, hasMore: p.hasMore),
      ),
      err: Result.err,
    );
  }
}
