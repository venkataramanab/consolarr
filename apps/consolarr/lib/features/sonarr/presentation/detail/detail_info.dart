// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/detail_providers.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// A section heading.
class DetailHeading extends StatelessWidget {
  const DetailHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Overview, facts and links of a series. Only what the server returned is
/// shown; absent sections are omitted. All text is plain text.
class DetailInfo extends StatelessWidget {
  const DetailInfo({
    required this.detail,
    required this.lookups,
    required this.now,
    required this.onOpenLink,
    super.key,
  });

  final SonarrSeriesDetail detail;

  /// Profile and tag names, when they could be loaded.
  final DetailLookups? lookups;
  final DateTime now;
  final void Function(Uri uri) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final series = detail.summary;
    final next = nextAiringText(l10n, series.nextAiring, now);
    final profile = lookups?.profileName(series.qualityProfileId);
    final tags = lookups?.tagLabels(series.tags) ?? const <String>[];
    final rating = detail.rating;
    final facts = <(String, String)>[
      if (statusText(l10n, series.status) case final s?)
        (l10n.sonarrDetailFieldStatus, s),
      if (series.network != null)
        (l10n.sonarrDetailFieldNetwork, series.network!),
      if (detail.path != null) (l10n.sonarrDetailFieldPath, detail.path!),
      if (profile != null) (l10n.sonarrDetailFieldProfile, profile),
      if (tags.isNotEmpty) (l10n.sonarrDetailFieldTags, tags.join(', ')),
      if (next != null) (l10n.sonarrDetailFieldNextAiring, next),
      if (detail.airTime != null)
        (l10n.sonarrDetailFieldAirTime, detail.airTime!),
      if (rating != null)
        (
          l10n.sonarrDetailFieldRating,
          l10n.sonarrDetailRatingValue(rating.value, rating.votes),
        ),
      if (detail.runtime != null)
        (
          l10n.sonarrDetailFieldRuntime,
          l10n.sonarrDetailRuntimeMinutes(detail.runtime!),
        ),
      if (detail.certification != null)
        (l10n.sonarrDetailFieldCertification, detail.certification!),
      if (detail.genres.isNotEmpty)
        (l10n.sonarrDetailFieldGenres, detail.genres.join(', ')),
      if (detail.cast.isNotEmpty)
        (l10n.sonarrDetailFieldCast, detail.cast.join(', ')),
    ];
    final links = detail.externalLinks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail.overview != null) ...[
          DetailHeading(l10n.sonarrDetailOverview),
          // Plain text only: never interpreted as markup.
          Text(detail.overview!),
          const SizedBox(height: ConsolarrSpacing.section),
        ],
        if (facts.isNotEmpty) ...[
          DetailHeading(l10n.sonarrDetailInfo),
          for (final (label, value) in facts) _Fact(label: label, value: value),
          const SizedBox(height: ConsolarrSpacing.section),
        ],
        if (links.isNotEmpty) ...[
          DetailHeading(l10n.sonarrDetailLinks),
          Wrap(
            spacing: ConsolarrSpacing.sm,
            runSpacing: ConsolarrSpacing.sm,
            children: [
              for (final link in links)
                _LinkButton(
                  name: _linkName(l10n, link.kind),
                  onPressed: () => onOpenLink(link.uri),
                ),
            ],
          ),
          const SizedBox(height: ConsolarrSpacing.section),
        ],
      ],
    );
  }

  static String _linkName(AppLocalizations l10n, SonarrExternalLinkKind kind) =>
      switch (kind) {
        SonarrExternalLinkKind.imdb => l10n.sonarrDetailLinkImdb,
        SonarrExternalLinkKind.tvdb => l10n.sonarrDetailLinkTvdb,
        SonarrExternalLinkKind.tmdb => l10n.sonarrDetailLinkTmdb,
        SonarrExternalLinkKind.tvMaze => l10n.sonarrDetailLinkTvMaze,
      };
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = context.roles;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ConsolarrSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: roles.textSecondary,
              ),
            ),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.name, required this.onPressed});

  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.sonarrDetailLinkSemantics(name),
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(name),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            ConsolarrSpacing.minTapTarget,
            ConsolarrSpacing.minTapTarget,
          ),
        ),
      ),
    );
  }
}
