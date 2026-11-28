// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';

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
  rows.sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
  return rows;
}
