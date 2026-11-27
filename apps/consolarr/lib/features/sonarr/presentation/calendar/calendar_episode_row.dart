// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/series_views.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// "S1E4" for [e].
String episodeCode(AppLocalizations l10n, SonarrEpisode e) =>
    l10n.sonarrCalendarEpisodeCode(e.seasonNumber, e.episodeNumber);

/// Premiere / finale tag text, or null.
String? episodeTag(AppLocalizations l10n, SonarrEpisode e) {
  if (e.finaleType != null && e.finaleType!.isNotEmpty) {
    return l10n.sonarrCalendarTagFinale;
  }
  if (e.episodeNumber == 1 && e.seasonNumber > 0) {
    return l10n.sonarrCalendarTagPremiere;
  }
  return null;
}

/// Downloaded / missing / not aired yet, as icon and text.
Widget episodeStatusChip(AppLocalizations l10n, SonarrEpisode e, DateTime now) {
  if (e.hasFile) {
    return StatusChip(
      label: l10n.sonarrCalendarStatusDownloaded,
      icon: Icons.check_circle_outline,
      tone: StatusTone.success,
    );
  }
  final airs = e.airs;
  if (airs == null || airs.isAfter(now)) {
    return StatusChip(
      label: l10n.sonarrCalendarStatusUnaired,
      icon: Icons.schedule,
      tone: StatusTone.info,
    );
  }
  return StatusChip(
    label: l10n.sonarrCalendarStatusMissing,
    icon: Icons.warning_amber_outlined,
    tone: StatusTone.warning,
  );
}

/// Local air time as text ("8:00 PM" / "20:00"), or null without a time.
String? airTimeText(BuildContext context, SonarrEpisode e) {
  final utc = e.airDateUtc;
  if (utc == null) return null;
  final local = utc.toLocal();
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: local.hour, minute: local.minute),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// One calendar row: series poster, series title, episode code, name, time,
/// tags and status. Tapping opens the series.
class CalendarEpisodeRow extends StatelessWidget {
  const CalendarEpisodeRow({
    required this.episode,
    required this.source,
    required this.now,
    required this.onOpen,
    super.key,
  });

  final SonarrEpisode episode;
  final ArtworkSource? source;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final series = episode.series;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final tag = episodeTag(l10n, episode);
    final time = airTimeText(context, episode);
    return MediaListTile(
      title: series?.title ?? episodeCode(l10n, episode),
      metadata: [
        if (series != null) episodeCode(l10n, episode),
        ?episode.title,
        ?time,
        if (!episode.monitored) l10n.sonarrCalendarUnmonitoredTag,
      ],
      leading: series == null
          ? const ArtworkPlaceholder()
          : seriesArtwork(
              source,
              series,
              (MediaListTile.thumbWidth * dpr).round(),
            ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          episodeStatusChip(l10n, episode, now),
          if (tag != null) ...[
            const SizedBox(height: ConsolarrSpacing.xs),
            StatusChip(label: tag, icon: Icons.star_outline),
          ],
        ],
      ),
      onTap: onOpen,
    );
  }
}
