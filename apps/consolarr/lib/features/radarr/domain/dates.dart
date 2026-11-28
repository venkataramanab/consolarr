// SPDX-License-Identifier: GPL-3.0-or-later

/// The calendar day of a date-only value.
///
/// Radarr sends release dates (`inCinemas`, `digitalRelease`,
/// `physicalRelease`) as midnight UTC: they name a day, not an instant. Taking
/// them to the device zone with `toLocal()` moves them to the previous day
/// west of UTC. This returns a local midnight built from the UTC date
/// components, so grouping and formatting show the day the server means in
/// every zone. Real timestamps (`dateAdded`) keep using `toLocal()`.
DateTime calendarDayOf(DateTime dateOnly) {
  final u = dateOnly.toUtc();
  return DateTime(u.year, u.month, u.day);
}

// --- One rule for "today" -----------------------------------------------------
//
// A release date is a *date-only* value (midnight UTC naming a day); "today"
// is the *user's local calendar date*. Both are compared as date values
// (midnight UTC markers of a year, month and day), never as instants and never
// on the UTC day, so the calendar, the Upcoming list and the availability
// badges agree in every zone: a release dated the 10th is "today" for the
// whole local 10th, from local midnight to local midnight. Real timestamps
// (`dateAdded`) are instants and keep using `toLocal()`.

/// The user's calendar date at [instant], as a date value (midnight UTC).
DateTime localDateOf(DateTime instant) {
  final l = instant.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

/// The calendar date a date-only [release] value names, as a date value.
DateTime releaseDateOf(DateTime release) {
  final u = release.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

/// Whether the day [release] names is before the user's today at [now].
bool isReleaseDayBefore(DateTime release, DateTime now) =>
    releaseDateOf(release).isBefore(localDateOf(now));

/// Whether the day [release] names is today or earlier for the user at [now].
bool hasReleaseDayArrived(DateTime release, DateTime now) =>
    !releaseDateOf(release).isAfter(localDateOf(now));
