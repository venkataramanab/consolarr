// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart'
    show
        ArrHistoryItem,
        ArrImageType,
        ArrQueueItem,
        ArrQueueState,
        RadarrClient,
        RadarrMovie,
        SonarrClient,
        SonarrEpisode;
import 'package:consolarr/features/dashboard/application/dashboard_dates.dart';
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/radarr/radarr_routes.dart' show radarrRoute;
import 'package:consolarr/features/sonarr/sonarr_routes.dart'
    show sonarrRoute, sonarrSeriesLocation;
import 'package:dio/dio.dart';

/// Days ahead the upcoming card looks.
const kUpcomingDays = 14;

/// Imports asked from the history. A season pack imports many episodes of one
/// series, so many more rows than posters are read; the list is cut to
/// [kCarouselItems] after one entry per series or movie is kept.
const kRecentImports = 100;

/// Radarr has the route `movie/:id` under its tab but no helper for it.
String _radarrMovieLocation(int id) => '$radarrRoute/movie/$id';

const _sonarrTab = DashboardLink(
  sonarrRoute,
  DashboardTarget.tab,
  DashboardDestination.sonarr,
);
const _radarrTab = DashboardLink(
  radarrRoute,
  DashboardTarget.tab,
  DashboardDestination.radarr,
);

// --- Sonarr ----------------------------------------------------------------

SonarrClient _sonarr(SourceContext c) => SonarrClient(
  dio: c.dio,
  parseRunner: c.runner,
  onRowsSkipped: c.onRowsSkipped,
);

RadarrClient _radarr(SourceContext c) => RadarrClient(
  dio: c.dio,
  parseRunner: c.runner,
  onRowsSkipped: c.onRowsSkipped,
);

final DashboardSource sonarrDashboardSource = DashboardSource(
  activity: (c) async => (await _sonarr(
    c,
  ).queue()).map((items) => summarizeQueue(items, _sonarrTab)),
  upcoming: (c) async {
    final today = calendarDay(c.now, c.utcOffset);
    final client = _sonarr(c);
    // The server reads the dates as UTC days: one day more on each side, and
    // the local day decides on the client.
    final r = await client.calendar(
      start: today.subtract(const Duration(days: 1)),
      end: today.add(const Duration(days: kUpcomingDays + 1)),
    );
    return r.map(
      (episodes) => sonarrUpcomingItems(
        episodes,
        today: today,
        utcOffset: c.utcOffset,
        dio: c.connection.dio,
        artwork: (e) => e.series == null
            ? null
            : client.artworkUri(e.series!, ArrImageType.poster),
      ),
    );
  },
  recent: (c) async {
    final client = _sonarr(c);
    final r = await client.recentImports(limit: kRecentImports);
    return r.map(
      (rows) => recentItems(
        rows,
        dio: c.connection.dio,
        artwork: (h) => client.artworkUriFor(h.images, ArrImageType.poster),
        link: (h) => h.seriesId == null
            ? _sonarrTab
            : DashboardLink(
                sonarrSeriesLocation(h.seriesId!),
                DashboardTarget.detail,
                DashboardDestination.series,
              ),
        mediaId: (h) => h.seriesId,
        season: (h) => h.seasonNumber,
        episode: (h) => h.episodeNumber,
      ),
    );
  },
);

// --- Radarr ----------------------------------------------------------------

final DashboardSource radarrDashboardSource = DashboardSource(
  activity: (c) async => (await _radarr(
    c,
  ).queue()).map((items) => summarizeQueue(items, _radarrTab)),
  upcoming: (c) async {
    final today = calendarDay(c.now, c.utcOffset);
    final client = _radarr(c);
    final r = await client.calendar(
      today,
      today.add(const Duration(days: kUpcomingDays)),
    );
    return r.map(
      (movies) => radarrUpcomingItems(
        movies,
        today: today,
        dio: c.connection.dio,
        artwork: (m) => client.artworkUri(m, ArrImageType.poster),
      ),
    );
  },
  recent: (c) async {
    final client = _radarr(c);
    final r = await client.recentImports(limit: kRecentImports);
    return r.map(
      (rows) => recentItems(
        rows,
        dio: c.connection.dio,
        artwork: (h) => client.artworkUriFor(h.images, ArrImageType.poster),
        link: (h) => h.movieId == null || h.movieId! <= 0
            ? _radarrTab
            : DashboardLink(
                _radarrMovieLocation(h.movieId!),
                DashboardTarget.detail,
                DashboardDestination.movie,
              ),
        mediaId: (h) => h.movieId,
        season: (_) => null,
        episode: (_) => null,
      ),
    );
  },
);

// --- pure mapping (tested without a network) ---------------------------------

ActivityState _activityState(ArrQueueState s) => switch (s) {
  ArrQueueState.downloading => ActivityState.downloading,
  ArrQueueState.paused => ActivityState.paused,
  ArrQueueState.queued || ArrQueueState.delayed => ActivityState.queued,
  ArrQueueState.importPending ||
  ArrQueueState.importing => ActivityState.importing,
  ArrQueueState.completed => ActivityState.completed,
  ArrQueueState.importFailed ||
  ArrQueueState.downloadFailed ||
  ArrQueueState.clientUnavailable ||
  ArrQueueState.warning => ActivityState.attention,
  ArrQueueState.ignored || ArrQueueState.unknown => ActivityState.queued,
};

ActivityState _effectiveState(ArrQueueItem i) {
  final s = _activityState(i.state);
  if (s == ActivityState.attention) return s;
  if (i.hasWarnings && s != ActivityState.completed) {
    return ActivityState.attention;
  }
  return s;
}

/// The activity of one Sonarr or Radarr queue. Counts cover the whole queue;
/// only [kActivityRows] rows are kept: items that need attention first, then
/// the downloads closest to done.
ActivitySummary summarizeQueue(List<ArrQueueItem> items, DashboardLink link) {
  var active = 0;
  var attention = 0;
  final candidates = <(ArrQueueItem, ActivityState)>[];
  for (final item in items) {
    final state = _effectiveState(item);
    if (state == ActivityState.attention) attention++;
    if (state == ActivityState.downloading) active++;
    if (state == ActivityState.attention ||
        state == ActivityState.downloading ||
        state == ActivityState.importing) {
      candidates.add((item, state));
    }
  }
  int rank((ArrQueueItem, ActivityState) c) =>
      c.$2 == ActivityState.attention ? 0 : 1;
  candidates.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : b.$1.progress.compareTo(a.$1.progress);
  });
  return ActivitySummary(
    active: active,
    attention: attention,
    link: link,
    rows: [
      for (final (i, state) in candidates.take(kActivityRows))
        ActivityRow(
          id: 'q:${i.id}',
          title: (i.mediaTitle?.isNotEmpty ?? false) ? i.mediaTitle! : i.title,
          state: state,
          progress: i.progress,
          sizeLeft: i.sizeLeft,
          eta: i.timeLeft,
        ),
    ],
  );
}

/// Sonarr episodes airing from [today] on, soonest first. `airDateUtc` is an
/// instant, so its day is the one in the viewer's zone ([utcOffset]).
List<MediaItem> sonarrUpcomingItems(
  List<SonarrEpisode> episodes, {
  required DateTime today,
  required Duration utcOffset,
  required Dio dio,
  required Uri? Function(SonarrEpisode episode) artwork,
}) {
  final last = today.add(const Duration(days: kUpcomingDays));
  final dated = <({SonarrEpisode e, DateTime day, DateTime sort})>[];
  for (final e in episodes) {
    final series = e.series;
    if (series == null || series.title.isEmpty) continue;
    final instant = e.airDateUtc;
    final day = instant != null
        ? calendarDay(instant, utcOffset)
        : parseDayText(e.airDate);
    if (day == null || day.isBefore(today) || day.isAfter(last)) continue;
    dated.add((e: e, day: day, sort: instant?.toUtc() ?? day));
  }
  dated.sort((a, b) => a.sort.compareTo(b.sort));
  return [
    for (final d in dated.take(kCarouselItems))
      MediaItem(
        id: 'ep:${d.e.id}',
        title: d.e.series!.title,
        season: d.e.seasonNumber,
        episode: d.e.episodeNumber,
        day: d.day,
        dio: dio,
        artwork: artwork(d.e),
        link: DashboardLink(
          sonarrSeriesLocation(d.e.seriesId),
          DashboardTarget.detail,
          DashboardDestination.series,
        ),
      ),
  ];
}

/// Radarr movies with a release in the window, soonest first. The release
/// dates are date-only UTC values: their UTC components are the day, never
/// shifted into the viewer's zone.
List<MediaItem> radarrUpcomingItems(
  List<RadarrMovie> movies, {
  required DateTime today,
  required Dio dio,
  required Uri? Function(RadarrMovie movie) artwork,
}) {
  final last = today.add(const Duration(days: kUpcomingDays));
  final dated = <({RadarrMovie m, DateTime day, MovieRelease release})>[];
  for (final m in movies) {
    if (m.title.isEmpty) continue;
    ({DateTime day, MovieRelease release})? best;
    for (final candidate in [
      (m.inCinemas, MovieRelease.cinemas),
      (m.digitalRelease, MovieRelease.digital),
      (m.physicalRelease, MovieRelease.disc),
    ]) {
      final value = candidate.$1;
      if (value == null) continue;
      final day = dateOnlyDay(value);
      if (day.isBefore(today) || day.isAfter(last)) continue;
      if (best == null || day.isBefore(best.day)) {
        best = (day: day, release: candidate.$2);
      }
    }
    if (best != null) dated.add((m: m, day: best.day, release: best.release));
  }
  dated.sort((a, b) => a.day.compareTo(b.day));
  return [
    for (final d in dated.take(kCarouselItems))
      MediaItem(
        id: 'mv:${d.m.id}',
        title: d.m.title,
        day: d.day,
        release: d.release,
        dio: dio,
        artwork: artwork(d.m),
        link: d.m.id > 0
            ? DashboardLink(
                _radarrMovieLocation(d.m.id),
                DashboardTarget.detail,
                DashboardDestination.movie,
              )
            : _radarrTab,
      ),
  ];
}

/// One entry per series or movie, newest import first.
List<MediaItem> recentItems(
  List<ArrHistoryItem> rows, {
  required Dio dio,
  required Uri? Function(ArrHistoryItem row) artwork,
  required DashboardLink Function(ArrHistoryItem row) link,
  required int? Function(ArrHistoryItem row) mediaId,
  required int? Function(ArrHistoryItem row) season,
  required int? Function(ArrHistoryItem row) episode,
}) {
  final newestFirst = [...rows]
    ..sort(
      (a, b) => (b.date ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          .compareTo(
            a.date ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
    );
  final seen = <int>{};
  final out = <MediaItem>[];
  for (final row in newestFirst) {
    final title = row.title;
    if (title == null || title.isEmpty) continue;
    final media = mediaId(row);
    if (media != null && !seen.add(media)) continue;
    out.add(
      MediaItem(
        id: 'hist:${row.id}',
        title: title,
        season: season(row),
        episode: episode(row),
        at: row.date,
        dio: dio,
        artwork: artwork(row),
        link: link(row),
      ),
    );
    if (out.length >= kCarouselItems) break;
  }
  return out;
}
