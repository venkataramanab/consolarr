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
