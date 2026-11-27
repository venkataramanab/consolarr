// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';

/// Where a movie is in its release life (RAD-08 banner, RAD-05 badge).
enum Availability {
  /// No release date is known.
  unannounced,

  /// A release date is known and still ahead.
  comingSoon,
  inCinemas,
  releasedDigital,
  releasedPhysical,
}

/// Derives [Availability] from the three release dates and [now].
///
/// Dates are instants (Radarr sends UTC), compared as instants, so the answer
/// does not depend on the device time zone. A date counts as reached from its
/// exact instant on. The later stage wins: physical, then digital, then
/// cinemas; otherwise a future date means "coming soon".
Availability availabilityOf(RadarrMovie movie, DateTime now) {
  bool reached(DateTime? d) => d != null && !d.isAfter(now);
  if (reached(movie.physicalRelease)) return Availability.releasedPhysical;
  if (reached(movie.digitalRelease)) return Availability.releasedDigital;
  if (reached(movie.inCinemas)) return Availability.inCinemas;
  final anyDate =
      movie.inCinemas != null ||
      movie.digitalRelease != null ||
      movie.physicalRelease != null;
  return anyDate ? Availability.comingSoon : Availability.unannounced;
}

/// Whether a search can find the movie yet, given its minimum availability.
/// Used to split "missing" (searchable) from "upcoming".
///
/// `announced`, `tba` and an unknown value mean "as soon as it is in the
/// library": Radarr searches such a movie at once, with or without dates.
bool isReleasedForSearch(RadarrMovie movie, DateTime now) {
  final a = availabilityOf(movie, now);
  return switch (movie.minimumAvailability) {
    MinimumAvailability.announced ||
    MinimumAvailability.tba ||
    MinimumAvailability.unknown => true,
    MinimumAvailability.inCinemas =>
      a != Availability.unannounced && a != Availability.comingSoon,
    MinimumAvailability.released =>
      a == Availability.releasedDigital || a == Availability.releasedPhysical,
  };
}
