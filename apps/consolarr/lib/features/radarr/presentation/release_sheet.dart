// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/release_query.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/features/radarr/presentation/stand_ins/glass_sheet.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Opens the interactive release search for a movie (RAD-13).
Future<void> showReleaseSheet(BuildContext context, int movieId) {
  final l10n = context.l10n;
  return showGlassSheet<void>(
    context: context,
    title: l10n.radarrReleasesTitle,
    closeLabel: l10n.radarrClose,
    builder: (_) => ReleaseSheetBody(movieId: movieId),
  );
}

String sortText(AppLocalizations l10n, ReleaseSortKey k) => switch (k) {
  ReleaseSortKey.bestMatch => l10n.radarrReleaseSortBest,
  ReleaseSortKey.age => l10n.radarrReleaseSortAge,
  ReleaseSortKey.size => l10n.radarrReleaseSortSize,
  ReleaseSortKey.seeders => l10n.radarrReleaseSortSeeders,
  ReleaseSortKey.indexer => l10n.radarrReleaseSortIndexer,
  ReleaseSortKey.quality => l10n.radarrReleaseSortQuality,
};

/// Search field, sort and filter chips, and the result list.
class ReleaseSheetBody extends ConsumerStatefulWidget {
  const ReleaseSheetBody({required this.movieId, super.key});

  final int movieId;

  @override
  ConsumerState<ReleaseSheetBody> createState() => _ReleaseSheetBodyState();
}

class _ReleaseSheetBodyState extends ConsumerState<ReleaseSheetBody> {
  ReleaseSortKey _sort = ReleaseSortKey.bestMatch;
  ReleaseFilter _filter = const ReleaseFilter();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(releasesProvider(widget.movieId));
    final grabs = ref.watch(grabStatusProvider);
    return RadarrScreenView(
      screen: ScreenName.radarrInteractiveSearch,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.gutter,
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: l10n.radarrReleaseSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => _filter = _filter.copyWith(text: v)),
              ),
            ),
            _chips(l10n),
            Expanded(child: _results(context, async, grabs)),
          ],
        ),
      ),
    );
  }

  Widget _chips(AppLocalizations l10n) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: ConsolarrSpacing.gutter),
    child: Row(
      children: [
        PopupMenuButton<ReleaseSortKey>(
          tooltip: l10n.radarrReleaseSortAction,
          initialValue: _sort,
          onSelected: (k) => setState(() => _sort = k),
          itemBuilder: (_) => [
            for (final k in ReleaseSortKey.values)
              PopupMenuItem(value: k, child: Text(sortText(l10n, k))),
          ],
          child: Chip(
            avatar: const Icon(Icons.sort, size: 18),
            label: Text(l10n.radarrReleaseSortedBy(sortText(l10n, _sort))),
          ),
        ),
        const SizedBox(width: ConsolarrSpacing.sm),
        for (final a in ReleaseAcceptance.values) ...[
          ChoiceChip(
            label: Text(switch (a) {
              ReleaseAcceptance.all => l10n.radarrReleaseAll,
              ReleaseAcceptance.accepted => l10n.radarrReleaseAccepted,
              ReleaseAcceptance.rejected => l10n.radarrReleaseRejected,
            }),
            selected: _filter.acceptance == a,
            onSelected: (_) =>
                setState(() => _filter = _filter.copyWith(acceptance: a)),
          ),
          const SizedBox(width: ConsolarrSpacing.sm),
        ],
        for (final p in const ['torrent', 'usenet']) ...[
          FilterChip(
            label: Text(
              p == 'torrent'
                  ? l10n.radarrProtocolTorrent
                  : l10n.radarrProtocolUsenet,
            ),
            selected: _filter.protocol == p,
            onSelected: (on) => setState(
              () => _filter = _filter.copyWith(protocol: on ? p : null),
            ),
          ),
          const SizedBox(width: ConsolarrSpacing.sm),
        ],
        for (final r in const [2160, 1080, 720]) ...[
          FilterChip(
            label: Text(l10n.radarrResolution(r)),
            selected: _filter.resolution == r,
            onSelected: (on) => setState(
              () => _filter = _filter.copyWith(resolution: on ? r : null),
            ),
          ),
          const SizedBox(width: ConsolarrSpacing.sm),
        ],
      ],
    ),
  );

  Widget _results(
    BuildContext context,
    AsyncValue<Result<List<RadarrRelease>>> async,
    Map<String, GrabPhase> grabs,
  ) {
    final l10n = context.l10n;
    // Loading and error first: the previous movie's results must never show.
    if (async.isLoading) {
      return Semantics(
        label: l10n.radarrSearchingReleases,
        liveRegion: true,
        child: ExcludeSemantics(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
            itemCount: 6,
            itemBuilder: (_, _) => const Padding(
              padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: SkeletonBox(height: 84, borderRadius: ConsolarrRadii.card),
            ),
          ),
        ),
      );
    }
    final result = async.hasError ? null : async.value;
    if (result == null) {
      return radarrErrorView(
        context,
        const AppError(ErrorCategory.parseError),
        onRetry: () => ref.invalidate(releasesProvider(widget.movieId)),
      );
    }
    final error = result.errorOrNull;
    if (error != null) {
      return radarrErrorView(
        context,
        error,
        onRetry: () => ref.invalidate(releasesProvider(widget.movieId)),
      );
    }
    final all = result.valueOrNull!;
    if (all.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        headline: l10n.radarrNoReleasesHeadline,
        message: l10n.radarrNoReleasesMessage,
        actionLabel: l10n.radarrRetry,
        onAction: () => ref.invalidate(releasesProvider(widget.movieId)),
      );
    }
    final rows = applyReleaseQuery(all, _sort, _filter);
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.filter_alt_off_outlined,
        headline: l10n.radarrNoReleaseMatchHeadline,
        message: l10n.radarrNoReleaseMatchMessage,
        actionLabel: l10n.radarrClearFilters,
        onAction: () => setState(() => _filter = const ReleaseFilter()),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
      itemCount: rows.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
        child: ReleaseRow(
          key: ValueKey(rows[i].guid),
          release: rows[i],
          phase: grabs[rows[i].guid],
          onGrab: () => _grab(context, rows[i]),
        ),
      ),
    );
  }

  Future<void> _grab(BuildContext context, RadarrRelease release) async {
    if (release.rejected) {
      final ok = await confirmRejectedGrab(context, release);
      if (ok != true) return;
    }
    await ref.read(grabStatusProvider.notifier).grab(release);
  }
}

/// Rejected releases need a confirmation that shows the reasons.
Future<bool?> confirmRejectedGrab(BuildContext context, RadarrRelease release) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l10n.radarrRejectedGrabTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.radarrRejectedGrabMessage),
            const SizedBox(height: ConsolarrSpacing.sm),
            for (final reason in release.rejections)
              Padding(
                padding: const EdgeInsets.only(bottom: ConsolarrSpacing.xs),
                child: Text('• $reason'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(l10n.radarrCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l10n.radarrGrabAnyway),
        ),
      ],
    ),
  );
}

/// One release: facts at a glance, reasons and formats when expanded.
class ReleaseRow extends StatefulWidget {
  const ReleaseRow({
    required this.release,
    required this.phase,
    required this.onGrab,
    super.key,
  });

  final RadarrRelease release;
  final GrabPhase? phase;
  final VoidCallback onGrab;

  @override
  State<ReleaseRow> createState() => _ReleaseRowState();
}

class _ReleaseRowState extends State<ReleaseRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final roles = context.roles;
    final r = widget.release;
    final facts = [
      ?r.qualityName,
      sizeText(l10n, r.size),
      ageHoursText(l10n, r.ageHours),
      if (r.seeders != null) l10n.radarrSeeders(r.seeders!),
      ?r.indexer,
    ].join(dot);
    final phase = widget.phase;
    final (label, icon) = switch (phase) {
      GrabPhase.grabbing => (l10n.radarrGrabbing, Icons.downloading),
      GrabPhase.grabbed => (l10n.radarrGrabbed, Icons.check),
      GrabPhase.failed => (l10n.radarrGrabFailedRetry, Icons.refresh),
      null => (l10n.radarrDownload, Icons.download),
    };
    return Material(
      color: roles.card,
      borderRadius: ConsolarrRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Release names are plain text from the server.
            Text(
              r.title,
              maxLines: _open ? null : 2,
              overflow: _open ? null : TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: ConsolarrSpacing.xs),
            Text(facts, style: theme.textTheme.bodyMedium),
            const SizedBox(height: ConsolarrSpacing.xs),
            Wrap(
              spacing: ConsolarrSpacing.sm,
              runSpacing: ConsolarrSpacing.xs,
              children: [
                if (r.rejected)
                  StatusChip(
                    label: l10n.radarrRejectedChip,
                    icon: Icons.block,
                    tone: StatusTone.warning,
                  ),
              ],
            ),
            if (_open) ...[
              if (r.rejections.isNotEmpty) ...[
                const SizedBox(height: ConsolarrSpacing.sm),
                Text(
                  l10n.radarrRejectionReasons,
                  style: theme.textTheme.labelLarge,
                ),
                for (final reason in r.rejections) Text('• $reason'),
              ],
              if (r.customFormats.isNotEmpty) ...[
                const SizedBox(height: ConsolarrSpacing.sm),
                Text(
                  l10n.radarrCustomFormats,
                  style: theme.textTheme.labelLarge,
                ),
                Text(r.customFormats.join(', ')),
              ],
            ],
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _open = !_open),
                  icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
                  label: Text(_open ? l10n.radarrCollapse : l10n.radarrExpand),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      phase == GrabPhase.grabbing || phase == GrabPhase.grabbed
                      ? null
                      : widget.onGrab,
                  icon: Icon(icon),
                  label: Text(label),
                ),
              ],
            ),
            if (phase == GrabPhase.failed)
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.radarrGrabFailed,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: roles.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String ageHoursText(AppLocalizations l10n, int hours) => hours < 48
    ? l10n.radarrReleaseAgeHours(hours)
    : l10n.radarrReleaseAgeDays(hours ~/ 24);
