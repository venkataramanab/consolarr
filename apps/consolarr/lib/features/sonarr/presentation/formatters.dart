// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:l10n/l10n.dart';

/// "just now", "5 minutes ago", ... for the offline banner.
String ageText(AppLocalizations l10n, Duration age) {
  if (age.inMinutes < 1) return l10n.sonarrAgeJustNow;
  if (age.inHours < 1) return l10n.sonarrAgeMinutes(age.inMinutes);
  if (age.inDays < 1) return l10n.sonarrAgeHours(age.inHours);
  return l10n.sonarrAgeDays(age.inDays);
}

/// Size on disk with one decimal and a unit. Digits and separators come from
/// the ARB number format, so they localize (like the torrents formatter).
String sizeText(AppLocalizations l10n, int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  const tb = 1024 * gb;
  if (bytes >= tb) return l10n.sonarrSizeTb(bytes / tb);
  if (bytes >= gb) return l10n.sonarrSizeGb(bytes / gb);
  return l10n.sonarrSizeMb(bytes / mb);
}

/// Relative "next airing" label, or null when nothing is scheduled.
String? nextAiringText(AppLocalizations l10n, DateTime? next, DateTime now) {
  if (next == null) return null;
  final a = DateTime(now.year, now.month, now.day);
  final local = next.toLocal();
  final b = DateTime(local.year, local.month, local.day);
  final days = b.difference(a).inDays;
  if (days <= 0) return l10n.sonarrNextAiringToday;
  if (days == 1) return l10n.sonarrNextAiringTomorrow;
  return l10n.sonarrNextAiringInDays(days);
}

/// Text for a known status, or null for `unknown` (no badge).
String? statusText(AppLocalizations l10n, SeriesStatus status) =>
    switch (status) {
      SeriesStatus.continuing => l10n.sonarrStatusContinuing,
      SeriesStatus.ended => l10n.sonarrStatusEnded,
      SeriesStatus.upcoming => l10n.sonarrStatusUpcoming,
      SeriesStatus.deleted => l10n.sonarrStatusDeleted,
      SeriesStatus.unknown => null,
    };
