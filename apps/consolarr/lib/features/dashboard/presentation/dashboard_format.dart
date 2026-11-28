// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_dates.dart';
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// A size such as `1.5 MB`, with the locale's digits (binary multiples).
String formatBytes(AppLocalizations l10n, int bytes) {
  final b = bytes < 0 ? 0 : bytes;
  const k = 1024;
  if (b < k) return l10n.dashboardUnitB(b.toDouble());
  if (b < k * k) return l10n.dashboardUnitKB(b / k);
  if (b < k * k * k) return l10n.dashboardUnitMB(b / (k * k));
  if (b < k * k * k * k) return l10n.dashboardUnitGB(b / (k * k * k));
  return l10n.dashboardUnitTB(b / (k * k * k * k));
}

/// A rate such as `1.5 MB/s`; the unit never wraps.
String formatSpeed(AppLocalizations l10n, int bytesPerSecond) =>
    l10n.dashboardSpeedPerSecond(formatBytes(l10n, bytesPerSecond));

/// A short duration: `under 1 min`, `12 min`, `3 h 5 min`, `2 d 4 h`.
String formatDuration(AppLocalizations l10n, Duration d) {
  final minutes = d.inMinutes < 0 ? 0 : d.inMinutes;
  if (minutes < 1) return l10n.dashboardDurationLess;
  if (minutes < 60) return l10n.dashboardDurationMinutes(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) return l10n.dashboardDurationHours(hours, minutes % 60);
  return l10n.dashboardDurationDays(hours ~/ 24, hours % 24);
}

/// "just now", "5 minutes ago", "2 hours ago", "3 days ago".
String ageText(AppLocalizations l10n, DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return l10n.dashboardAgeNow;
  if (d.inMinutes < 60) return l10n.dashboardAgeMinutes(d.inMinutes);
  if (d.inHours < 24) return l10n.dashboardAgeHours(d.inHours);
  return l10n.dashboardAgeDays(d.inDays);
}

/// "today", "tomorrow", "in 3 days" for [day] seen from [today] (both UTC
/// midnights from `calendarDay` / `dateOnlyDay`).
String relativeDay(AppLocalizations l10n, DateTime today, DateTime day) {
  final n = daysBetween(today, day);
  if (n <= 0) return l10n.dashboardDayToday;
  if (n == 1) return l10n.dashboardDayTomorrow;
  return l10n.dashboardDayInDays(n);
}

/// The one-line detail under a carousel item.
String itemDetails(
  AppLocalizations l10n,
  MediaItem item, {
  required DateTime now,
  required Duration utcOffset,
}) {
  final String first;
  if (item.isEpisode) {
    first = l10n.dashboardEpisodeCode(item.season!, item.episode!);
  } else {
    first = switch (item.release) {
      MovieRelease.cinemas => l10n.dashboardMovieInCinemas,
      MovieRelease.digital => l10n.dashboardMovieDigital,
      MovieRelease.disc => l10n.dashboardMovieDisc,
      MovieRelease.none => l10n.dashboardMovieLabel,
    };
  }
  final String? second;
  if (item.day != null) {
    second = relativeDay(l10n, calendarDay(now, utcOffset), item.day!);
  } else if (item.at != null) {
    second = ageText(l10n, item.at!, now);
  } else {
    second = null;
  }
  return second == null ? first : l10n.dashboardItemSubtitle(first, second);
}

/// Row styling of an activity state: the fill state, an icon and the label.
(ProgressRowState, IconData, String) activityStyle(
  AppLocalizations l10n,
  ActivityState state,
) => switch (state) {
  ActivityState.downloading => (
    ProgressRowState.active,
    Icons.arrow_downward,
    l10n.dashboardStateDownloading,
  ),
  ActivityState.stalled => (
    ProgressRowState.queued,
    Icons.hourglass_empty,
    l10n.dashboardStateStalled,
  ),
  ActivityState.checking => (
    ProgressRowState.idle,
    Icons.manage_search,
    l10n.dashboardStateChecking,
  ),
  ActivityState.queued => (
    ProgressRowState.queued,
    Icons.schedule,
    l10n.dashboardStateQueued,
  ),
  ActivityState.paused => (
    ProgressRowState.paused,
    Icons.pause,
    l10n.dashboardStatePaused,
  ),
  ActivityState.importing => (
    ProgressRowState.active,
    Icons.move_to_inbox,
    l10n.dashboardStateImporting,
  ),
  ActivityState.completed => (
    ProgressRowState.idle,
    Icons.check_circle_outline,
    l10n.dashboardStateCompleted,
  ),
  ActivityState.seeding => (
    ProgressRowState.idle,
    Icons.arrow_upward,
    l10n.dashboardStateSeeding,
  ),
  ActivityState.attention => (
    ProgressRowState.error,
    Icons.error_outline,
    l10n.dashboardStateAttention,
  ),
};
