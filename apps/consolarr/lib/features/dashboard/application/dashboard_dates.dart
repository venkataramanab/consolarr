// SPDX-License-Identifier: GPL-3.0-or-later

/// The calendar day of [instant] in a zone that is [utcOffset] ahead of UTC,
/// as a UTC midnight (so two days subtract exactly, DST or not).
///
/// Used for instants only (Sonarr's `airDateUtc`, "now"). Date-only values
/// (Radarr release dates) never go through here: they are taken as they are,
/// with [dateOnlyDay], because shifting them by the zone moves them to the
/// wrong day.
DateTime calendarDay(DateTime instant, Duration utcOffset) {
  final shifted = instant.toUtc().add(utcOffset);
  return DateTime.utc(shifted.year, shifted.month, shifted.day);
}

/// The day of a date-only value that arrives as a UTC instant at midnight
/// (`2026-03-10T00:00:00Z`): its UTC components, with no zone shift.
DateTime dateOnlyDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Whole days from [today] to [day] (both UTC midnights); negative in the
/// past.
int daysBetween(DateTime today, DateTime day) => day.difference(today).inDays;

/// A plain `yyyy-MM-dd` value as a day, or `null`.
DateTime? parseDayText(String? text) {
  if (text == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, mo, d);
}
