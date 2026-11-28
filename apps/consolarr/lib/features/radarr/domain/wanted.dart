// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/features/radarr/domain/dates.dart';

/// Scopes of the wanted list (RAD-15). "Cutoff unmet" is a later feature.
enum WantedScope { released, upcoming, allMissing }

/// Monitored movies without a file, split by whether a search can find them
/// yet. Derived from the library, so it also works from the offline cache.
List<RadarrMovie> wantedMovies(
  List<RadarrMovie> library,
  WantedScope scope,
  DateTime now,
) {
  final rows = [
    for (final m in library)
      if (m.monitored && !m.hasFile)
        if (switch (scope) {
          WantedScope.released => isReleasedForSearch(m, now),
          WantedScope.upcoming => !isReleasedForSearch(m, now),
          WantedScope.allMissing => true,
        })
          m,
  ];
  final today = localDateOf(now);
  // Sort keys once per movie, not once per comparison.
  final keys = {
    for (final m in rows)
      m.id: scope == WantedScope.upcoming
          ? soonestUpcomingRelease(m, today)
          : latestRelease(m),
  };
  int byTitle(RadarrMovie a, RadarrMovie b) {
    final c = a.sortTitle.compareTo(b.sortTitle);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  rows.sort((a, b) {
    final x = keys[a.id];
    final y = keys[b.id];
    if (x == null && y == null) return byTitle(a, b);
    if (x == null) return 1; // no date: last
    if (y == null) return -1;
    final c = scope == WantedScope.upcoming ? x.compareTo(y) : y.compareTo(x);
    return c != 0 ? c : byTitle(a, b);
  });
  return rows;
}

/// The latest of the digital, physical and cinema release dates, or null.
/// Missing lists newest first by this date.
DateTime? latestRelease(RadarrMovie m) {
  DateTime? latest;
  for (final d in [m.digitalRelease, m.physicalRelease, m.inCinemas]) {
    if (d != null && (latest == null || d.isAfter(latest))) latest = d;
  }
  return latest;
}

/// The earliest release date that is not behind [today] (the user's local
/// date, see `localDateOf`), or null when none is ahead (or none is known).
/// Upcoming lists soonest first by this date.
///
/// Release dates are date-only values (midnight UTC), compared with [today] as
/// dates: the same rule as the calendar, whatever zone the device is in.
DateTime? soonestUpcomingRelease(RadarrMovie m, DateTime today) {
  DateTime? soonest;
  for (final d in [m.inCinemas, m.digitalRelease, m.physicalRelease]) {
    if (d == null || releaseDateOf(d).isBefore(today)) continue;
    if (soonest == null || d.isBefore(soonest)) soonest = d;
  }
  return soonest;
}
