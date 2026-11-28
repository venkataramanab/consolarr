// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_day.dart';
import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_format.dart';
import 'package:consolarr/features/dashboard/presentation/dashboard_widgets.dart';
import 'package:consolarr/src/images/secure_image_provider.dart';
import 'package:consolarr/src/providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// DSH-03: episodes and movies coming out in the next two weeks.
class UpcomingCard extends ConsumerWidget {
  const UpcomingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(dashboardProvider.select((s) => s.upcoming));
    return _MediaCard(
      card: DashboardCard.upcoming,
      heading: l10n.dashboardUpcomingHeading,
      state: state,
      notConfigured: l10n.dashboardUpcomingNotConfigured,
      emptyHeading: l10n.dashboardUpcomingEmptyHeading,
      emptyBody: l10n.dashboardUpcomingEmptyBody,
      emptyIcon: Icons.event_available_outlined,
    );
  }
}

/// DSH-04: what was imported lately.
class RecentCard extends ConsumerWidget {
  const RecentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(dashboardProvider.select((s) => s.recent));
    return _MediaCard(
      card: DashboardCard.recent,
      heading: l10n.dashboardRecentHeading,
      state: state,
      notConfigured: l10n.dashboardRecentNotConfigured,
      emptyHeading: l10n.dashboardRecentEmptyHeading,
      emptyBody: l10n.dashboardRecentEmptyBody,
      emptyIcon: Icons.inbox_outlined,
    );
  }
}

class _MediaCard extends ConsumerWidget {
  const _MediaCard({
    required this.card,
    required this.heading,
    required this.state,
    required this.notConfigured,
    required this.emptyHeading,
    required this.emptyBody,
    required this.emptyIcon,
  });

  final DashboardCard card;
  final String heading;
  final CardState<List<MediaItem>> state;
  final String notConfigured;
  final String emptyHeading;
  final String emptyBody;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return DashboardCardFrame(
      heading: heading,
      child: switch (state) {
        CardLoading() => const DashboardSkeleton(carousel: true),
        CardNotConfigured() => DashboardCardMessage(
          icon: emptyIcon,
          headline: notConfigured,
          actionLabel: l10n.dashboardSetupCta,
          onAction: () => openSetup(context),
        ),
        CardEmpty() => DashboardCardMessage(
          icon: emptyIcon,
          headline: emptyHeading,
          message: emptyBody,
        ),
        CardError(:final slices) => _Slices(
          card: card,
          heading: heading,
          slices: slices,
        ),
        CardData(:final slices) => _Slices(
          card: card,
          heading: heading,
          slices: slices,
        ),
      },
    );
  }
}

class _Slices extends StatelessWidget {
  const _Slices({
    required this.card,
    required this.heading,
    required this.slices,
  });

  final DashboardCard card;
  final String heading;
  final List<CardSlice<List<MediaItem>>> slices;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, slice) in slices.indexed) ...[
        if (i > 0) const SizedBox(height: ConsolarrSpacing.md),
        switch (slice) {
          SliceData<List<MediaItem>>() => _MediaSlice(
            card: card,
            heading: heading,
            slice: slice,
          ),
          SliceFailed<List<MediaItem>>() => DashboardSliceError(
            slice: slice,
            card: card,
          ),
          SliceLoading<List<MediaItem>>() => const DashboardSkeleton(
            carousel: true,
          ),
        },
      ],
    ],
  );
}

class _MediaSlice extends ConsumerWidget {
  const _MediaSlice({
    required this.card,
    required this.heading,
    required this.slice,
  });

  final DashboardCard card;
  final String heading;
  final SliceData<List<MediaItem>> slice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = slice.value;
    // Rebuilds at local midnight: "tomorrow" becomes "today".
    ref.watch(dashboardDayProvider);
    final now = ref.read(clockProvider)();
    final offset = now.timeZoneOffset;
    final width = posterWidth(context);
    final cachedAt = slice.cachedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cachedAt != null) ...[
          DashboardCachedBanner(cachedAt: cachedAt, now: now),
          const SizedBox(height: ConsolarrSpacing.sm),
        ],
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.dashboardCarouselSemantics(heading, items.length),
          child: SizedBox(
            height: width * 1.5,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final details = itemDetails(
                  l10n,
                  item,
                  now: now,
                  utcOffset: offset,
                );
                return Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: ConsolarrSpacing.sm,
                  ),
                  child: SizedBox(
                    width: width,
                    child: PosterCard(
                      title: item.title,
                      subtitle: details,
                      semanticsLabel: l10n.dashboardItemSemantics(
                        item.title,
                        details,
                        index + 1,
                        items.length,
                      ),
                      imageBuilder: (context, cacheWidth) =>
                          _poster(item, cacheWidth),
                      onTap: () =>
                          openDashboardLink(context, ref, card, item.link),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Artwork through the server's own Dio, decoded at display size; a
/// placeholder when there is none or it fails.
Widget _poster(MediaItem item, int cacheWidth) {
  final uri = item.artwork;
  if (uri == null) return const ArtworkPlaceholder();
  return Image(
    image: ResizeImage(
      SecureNetworkImage(dio: item.dio, uri: uri),
      width: cacheWidth,
    ),
    fit: BoxFit.cover,
    excludeFromSemantics: true,
    gaplessPlayback: true,
    errorBuilder: (context, error, stack) => const ArtworkPlaceholder(),
  );
}
