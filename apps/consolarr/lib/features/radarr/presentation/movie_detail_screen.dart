// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/features/radarr/domain/dates.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/edit_sheet.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/release_sheet.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/shared/l10n/join_parts.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// The only host trailer links may point at, and the only shape of id.
final _trailerId = RegExp(r'^[A-Za-z0-9_-]{6,32}$');

/// The trailer URL for a YouTube [id], or null when the id is not plausible.
/// Built from the id only; nothing the server sends as a URL is used.
Uri? trailerUri(String? id) => id == null || !_trailerId.hasMatch(id)
    ? null
    : Uri.https('www.youtube.com', '/watch', {'v': id});

/// Movie detail (RAD-08): backdrop with scrim, availability banner, actions,
/// overview, file info, ratings, trailer link and collection (plain text).
class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({required this.movieId, super.key});

  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(movieDetailProvider(movieId));
    Future<void> refresh() =>
        ref.read(movieDetailProvider(movieId).notifier).refresh();

    Widget frame(Widget child, {String? title}) => RadarrScreenView(
      screen: ScreenName.radarrMovieDetail,
      child: Scaffold(
        appBar: AppBar(title: Text(title ?? l10n.radarrDetailTitle)),
        body: child,
      ),
    );

    if (async.isLoading) return frame(_DetailSkeleton());
    final state = async.hasError ? null : async.value;
    if (state == null) {
      return frame(
        radarrErrorView(
          context,
          const AppError(ErrorCategory.parseError),
          onRetry: refresh,
        ),
      );
    }
    return switch (state) {
      RadarrNoServer() => frame(radarrNoServerView(context)),
      RadarrGone() => frame(
        EmptyState(
          icon: Icons.movie_filter_outlined,
          headline: l10n.radarrGoneHeadline,
          message: l10n.radarrGoneMessage,
          actionLabel: l10n.radarrBack,
          onAction: () => Navigator.of(context).maybePop(),
        ),
      ),
      RadarrFailure(:final error) => frame(
        radarrErrorView(context, error, onRetry: refresh),
      ),
      RadarrData(:final snapshot) => frame(
        _Content(movie: snapshot.value, snapshot: snapshot, onRefresh: refresh),
        title: snapshot.value.title,
      ),
    };
  }
}

class _DetailSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.radarrLoadingLabel,
    liveRegion: true,
    child: const ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.all(ConsolarrSpacing.gutter),
        child: Column(
          children: [
            SkeletonBox(height: 180, borderRadius: ConsolarrRadii.card),
            SizedBox(height: ConsolarrSpacing.md),
            SkeletonBox(height: 40, borderRadius: ConsolarrRadii.card),
            SizedBox(height: ConsolarrSpacing.md),
            SkeletonBox(height: 120, borderRadius: ConsolarrRadii.card),
          ],
        ),
      ),
    ),
  );
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.movie,
    required this.snapshot,
    required this.onRefresh,
  });

  final RadarrMovie movie;
  final Snapshot<RadarrMovie> snapshot;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final source = ref.watch(artworkSourceProvider);
    final availability = availabilityOf(movie, now);
    final offline = snapshot.isOffline;
    final profilesAsync = ref.watch(qualityProfilesProvider);
    // Tag names are read here too (not shown on this screen): a failed read
    // is reported the same way as the profiles, and its retry reads both.
    final tagsAsync = ref.watch(tagsProvider);
    final profiles = profilesAsync.value ?? const [];
    final profileName = profiles
        .where((p) => p.id == movie.qualityProfileId)
        .map((p) => p.name)
        .firstOrNull;
    final searchPhase = ref.watch(searchPhaseProvider(movie.id));
    final trailer = trailerUri(movie.youTubeTrailerId);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final backdrop = source?.image(movie, ArrImageType.fanart);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (profilesAsync.hasError || tagsAsync.hasError)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.gutter,
              ),
              child: ListsFailedRow(),
            ),
          if (offline)
            Padding(
              padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
              child: offlineBanner(
                context,
                fetchedAt: snapshot.fetchedAt,
                now: now,
                onRetry: onRefresh,
              ),
            ),
          SizedBox(
            height: 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdrop == null)
                  const ArtworkPlaceholder(icon: Icons.movie_outlined)
                else
                  Image(
                    image: ResizeImage(backdrop, width: (width * dpr).round()),
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) =>
                        const ArtworkPlaceholder(icon: Icons.movie_outlined),
                  ),
                // Scrim so the text over artwork keeps its contrast.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        context.roles.page.withValues(alpha: 0),
                        context.roles.page,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ConsolarrSpacing.gutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    movie.title,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: ConsolarrSpacing.xs),
                Text(
                  joinParts(l10n, [
                    if (movie.year case final year?) l10n.plainInt(year),
                    if (movie.runtime != null)
                      l10n.radarrRuntime(movie.runtime!),
                    ?movie.certification,
                    ?movie.studio,
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: ConsolarrSpacing.md),
                _AvailabilityBanner(movie: movie, availability: availability),
                const SizedBox(height: ConsolarrSpacing.md),
                Wrap(
                  spacing: ConsolarrSpacing.sm,
                  runSpacing: ConsolarrSpacing.sm,
                  children: [
                    fileChip(l10n, movie),
                    StatusChip(
                      label: movie.monitored
                          ? l10n.radarrMonitored
                          : l10n.radarrUnmonitored,
                      icon: movie.monitored
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    if (movie.rating != null)
                      StatusChip(
                        label: l10n.radarrRating(movie.rating!),
                        icon: Icons.star_outline,
                      ),
                  ],
                ),
                const SizedBox(height: ConsolarrSpacing.md),
                _Actions(
                  movie: movie,
                  offline: offline,
                  searchPhase: searchPhase,
                ),
                if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                  const SizedBox(height: ConsolarrSpacing.lg),
                  _Section(
                    title: l10n.radarrOverview,
                    // Plain text only: server text is never interpreted.
                    child: Text(movie.overview!),
                  ),
                ],
                const SizedBox(height: ConsolarrSpacing.md),
                _Section(
                  title: l10n.radarrFileSection,
                  child: _FileInfo(movie: movie),
                ),
                const SizedBox(height: ConsolarrSpacing.md),
                _Section(
                  title: l10n.radarrDetailsSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profileName != null)
                        Text(
                          l10n.radarrLabelValue(
                            l10n.radarrQualityProfile,
                            profileName,
                          ),
                        ),
                      Text(
                        l10n.radarrLabelValue(
                          l10n.radarrMinimumAvailability,
                          minimumAvailabilityText(
                            l10n,
                            movie.minimumAvailability,
                          ),
                        ),
                      ),
                      if (movie.genres.isNotEmpty)
                        Text(
                          l10n.radarrLabelValue(
                            l10n.radarrGenres,
                            joinList(l10n, movie.genres),
                          ),
                        ),
                      if (movie.collectionTitle != null)
                        Text(l10n.radarrInCollection(movie.collectionTitle!)),
                    ],
                  ),
                ),
                if (trailer != null) ...[
                  const SizedBox(height: ConsolarrSpacing.md),
                  _Section(
                    title: l10n.radarrTrailer,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            trailer.toString(),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.radarrCopyTrailer,
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: trailer.toString()),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.radarrTrailerCopied),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: ConsolarrSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBanner extends StatelessWidget {
  const _AvailabilityBanner({required this.movie, required this.availability});

  final RadarrMovie movie;
  final Availability availability;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, tone) = availabilityStyle(availability);
    final date = switch (availability) {
      Availability.inCinemas => movie.inCinemas,
      Availability.releasedDigital => movie.digitalRelease,
      Availability.releasedPhysical => movie.physicalRelease,
      Availability.comingSoon =>
        movie.inCinemas ?? movie.digitalRelease ?? movie.physicalRelease,
      Availability.unannounced => null,
    };
    final label = availabilityText(l10n, availability);
    final text = date == null
        ? label
        : // Date-only value (midnight UTC): show the day it names.
          l10n.radarrAvailabilityOn(label, calendarDayOf(date));
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: StatusChip(label: text, icon: icon, tone: tone),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.movie,
    required this.offline,
    required this.searchPhase,
  });

  final RadarrMovie movie;
  final bool offline;
  final SearchPhase? searchPhase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final busy =
        searchPhase != null &&
        searchPhase != SearchPhase.done &&
        searchPhase != SearchPhase.failed &&
        searchPhase != SearchPhase.stillRunning;
    final (progressText, progressIcon) = switch (searchPhase) {
      SearchPhase.starting => (
        l10n.radarrSearchStarting,
        Icons.hourglass_empty,
      ),
      SearchPhase.queued => (l10n.radarrSearchQueued, Icons.schedule),
      SearchPhase.searching => (l10n.radarrSearchRunning, Icons.search),
      SearchPhase.done => (l10n.radarrSearchDone, Icons.check_circle_outline),
      SearchPhase.failed => (l10n.radarrSearchFailed, Icons.error_outline),
      SearchPhase.stillRunning => (
        l10n.radarrSearchStillRunning,
        Icons.schedule,
      ),
      null => (null, null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: ConsolarrSpacing.sm,
          runSpacing: ConsolarrSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: offline || busy
                  ? null
                  : () => ref
                        .read(searchStatusProvider.notifier)
                        .searchMovie(movie.id),
              icon: const Icon(Icons.search),
              label: Text(l10n.radarrSearchMovie),
            ),
            OutlinedButton.icon(
              onPressed: offline
                  ? null
                  : () => showReleaseSheet(context, movie.id),
              icon: const Icon(Icons.manage_search),
              label: Text(l10n.radarrInteractiveSearch),
            ),
            OutlinedButton.icon(
              onPressed: offline ? null : () => showEditSheet(context, movie),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.radarrEdit),
            ),
          ],
        ),
        if (offline)
          Padding(
            padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
            child: Text(
              l10n.radarrWritesDisabled,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (progressText != null)
          Padding(
            padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: StatusChip(
                label: progressText,
                icon: progressIcon!,
                tone: switch (searchPhase) {
                  SearchPhase.done => StatusTone.success,
                  SearchPhase.failed => StatusTone.error,
                  _ => StatusTone.info,
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: context.roles.card,
      borderRadius: ConsolarrRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.md),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: ConsolarrSpacing.xs),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _FileInfo extends StatelessWidget {
  const _FileInfo({required this.movie});

  final RadarrMovie movie;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final file = movie.movieFile;
    if (!movie.hasFile || file == null) {
      return Text(l10n.radarrNoFile);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          joinParts(l10n, [
            ?file.qualityName,
            sizeText(l10n, file.size),
            ?file.videoCodec,
            ?file.audioCodec,
          ]),
        ),
        if (file.dateAdded != null)
          Text(l10n.radarrImportedOn(file.dateAdded!.toLocal())),
      ],
    );
  }
}
