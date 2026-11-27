// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:l10n/l10n.dart';

/// Human-readable size, locale-aware (digits and separators come from the
/// ARB number formats). Binary multiples (1 KB = 1024 B).
String formatBytes(AppLocalizations l10n, int bytes) {
  final b = bytes < 0 ? 0 : bytes;
  const k = 1024;
  if (b < k) return l10n.torUnitB(b.toDouble());
  if (b < k * k) return l10n.torUnitKB(b / k);
  if (b < k * k * k) return l10n.torUnitMB(b / (k * k));
  if (b < k * k * k * k) return l10n.torUnitGB(b / (k * k * k));
  return l10n.torUnitTB(b / (k * k * k * k));
}

/// A transfer rate such as `1.5 MB/s`.
String formatSpeed(AppLocalizations l10n, int bytesPerSecond) =>
    l10n.torSpeedPerSecond(formatBytes(l10n, bytesPerSecond));

/// Short two-unit duration: `45s`, `12m`, `3h 5m`, `2d 4h`.
String formatDuration(AppLocalizations l10n, Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return l10n.torDurationSeconds(s);
  final minutes = s ~/ 60;
  if (minutes < 60) return l10n.torDurationMinutes(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return l10n.torDurationHoursMinutes(hours, minutes % 60);
  }
  return l10n.torDurationDaysHours(hours ~/ 24, hours % 24);
}
