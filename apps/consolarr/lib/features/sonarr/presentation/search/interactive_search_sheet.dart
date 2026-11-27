// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/release_controls.dart';
import 'package:consolarr/features/arr_common/presentation/release_row.dart';
import 'package:consolarr/features/sonarr/application/release_search.dart';
import 'package:consolarr/features/sonarr/presentation/screen_tracking.dart';
import 'package:consolarr/features/sonarr/presentation/search/release_row_mapper.dart';
import 'package:consolarr/features/sonarr/presentation/stand_ins/glass_sheet.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

export 'package:consolarr/features/sonarr/application/release_search.dart'
    show InteractiveSearchTarget;

/// Opens the large release-search sheet for [target]; [title] is the
/// (plain text) heading, for example the episode label.
Future<void> showInteractiveSearch({
  required BuildContext context,
  required InteractiveSearchTarget target,
  required String title,
}) => showGlassSheet<void>(
  context: context,
  title: title,
  closeLabel: context.l10n.sonarrReleaseClose,
  detents: GlassSheetDetents.full,
  builder: (context, controller) =>
      InteractiveSearchContent(target: target, controller: controller),
);

/// The body of the release sheet: search, sort, filter and the release list
/// with every state (searching, none, none match, error, results).
class InteractiveSearchContent extends ConsumerWidget {
  const InteractiveSearchContent({
    required this.target,
    this.controller,
    super.key,
  });

  final InteractiveSearchTarget target;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final releases = ref.watch(releaseSearchProvider(target));
    void retry() => ref.read(releaseSearchProvider(target).notifier).retry();
    // Loading and error come first: a reload keeps the previous value.
    final Widget body;
    if (releases.isLoading) {
      body = _Skeleton(label: l10n.sonarrReleaseLoading);
    } else if (releases.hasError) {
      final error = releases.error;
      final message = connectionErrorMessage(
        l10n,
        error is AppError ? error : const AppError(ErrorCategory.parseError),
      );
      body = ErrorState(
        headline: l10n.sonarrReleaseErrorHeadline,
        message: message.message,
        hint: message.hint,
        retryLabel: l10n.sonarrReleaseSearchAgain,
        onRetry: retry,
      );
    } else {
      final all = releases.value ?? const <ArrRelease>[];
      body = all.isEmpty
          ? EmptyState(
              icon: Icons.search_off,
              headline: l10n.sonarrReleaseNoneHeadline,
              message: l10n.sonarrReleaseNoneMessage,
              actionLabel: l10n.sonarrReleaseSearchAgain,
              onAction: retry,
            )
          : _ReleaseList(target: target, all: all, controller: controller);
    }
    return TrackScreen(screen: ScreenName.sonarrInteractiveSearch, child: body);
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
        itemCount: 5,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
          child: SkeletonBox(height: 120, borderRadius: ConsolarrRadii.card),
        ),
      ),
    ),
  );
}

String _sortLabel(AppLocalizations l10n, ReleaseSort s) => switch (s) {
  ReleaseSort.bestMatch => l10n.sonarrReleaseSortBestMatch,
  ReleaseSort.age => l10n.sonarrReleaseSortAge,
  ReleaseSort.size => l10n.sonarrReleaseSortSize,
  ReleaseSort.seeders => l10n.sonarrReleaseSortSeeders,
  ReleaseSort.indexer => l10n.sonarrReleaseSortIndexer,
  ReleaseSort.quality => l10n.sonarrReleaseSortQuality,
};

const _groupStatus = 'status';
const _groupProtocol = 'protocol';
const _groupResolution = 'resolution';
const _groupSource = 'source';

class _ReleaseList extends ConsumerWidget {
  const _ReleaseList({
    required this.target,
    required this.all,
    required this.controller,
  });

  final InteractiveSearchTarget target;
  final List<ArrRelease> all;
  final ScrollController? controller;

  List<ReleaseFilterGroup> _groups(AppLocalizations l10n, ReleaseView view) {
    final resolutions = {
      for (final r in all)
        if (r.resolution != null && r.resolution! > 0) r.resolution!,
    }.toList()..sort((a, b) => b.compareTo(a));
    final sources = {
      for (final r in all)
        if (r.source != null && r.source!.isNotEmpty) r.source!,
    }.toList()..sort();
    final protocols = {for (final r in all) r.protocol}
      ..remove(ArrProtocol.unknown);
    return [
      ReleaseFilterGroup(
        id: _groupStatus,
        label: l10n.sonarrReleaseGroupStatus,
        options: [
          ReleaseFilterOption(
            id: ReleaseDecision.accepted.name,
            label: l10n.sonarrReleaseAccepted,
            selected: view.decision == ReleaseDecision.accepted,
          ),
          ReleaseFilterOption(
            id: ReleaseDecision.rejected.name,
            label: l10n.sonarrReleaseRejected,
            selected: view.decision == ReleaseDecision.rejected,
          ),
        ],
      ),
      ReleaseFilterGroup(
        id: _groupProtocol,
        label: l10n.sonarrReleaseGroupProtocol,
        options: [
          for (final p in protocols)
            ReleaseFilterOption(
              id: p.name,
              label: protocolText(l10n, p) ?? '',
              selected: view.protocol == p,
            ),
        ],
      ),
      ReleaseFilterGroup(
        id: _groupResolution,
        label: l10n.sonarrReleaseGroupResolution,
        options: [
          for (final r in resolutions)
            ReleaseFilterOption(
              id: '$r',
              label: l10n.sonarrReleaseResolution('$r'),
              selected: view.resolutions.contains(r),
            ),
        ],
      ),
      ReleaseFilterGroup(
        id: _groupSource,
        label: l10n.sonarrReleaseGroupSource,
        options: [
          for (final s in sources)
            ReleaseFilterOption(
              id: s,
              label: s,
              selected: view.sources.contains(s),
            ),
        ],
      ),
    ];
  }

  void _toggle(WidgetRef ref, String group, String id) {
    ref.read(releaseViewProvider(target).notifier).update((v) {
      switch (group) {
        case _groupStatus:
          final d = ReleaseDecision.values.byName(id);
          return v.copyWith(
            decision: v.decision == d ? ReleaseDecision.all : d,
          );
        case _groupProtocol:
          final p = ArrProtocol.values.byName(id);
          return v.protocol == p
              ? v.copyWith(clearProtocol: true)
              : v.copyWith(protocol: p);
        case _groupResolution:
          final r = int.parse(id);
          final next = {...v.resolutions};
          if (!next.remove(r)) next.add(r);
          return v.copyWith(resolutions: next);
        default:
          final next = {...v.sources};
          if (!next.remove(id)) next.add(id);
          return v.copyWith(sources: next);
      }
    });
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    ArrRelease release,
  ) async {
    final notifier = ref.read(releaseGrabProvider(target).notifier);
    if (ref.read(releaseGrabProvider(target))[grabKey(release)] ==
        GrabStatus.maybeSent) {
      // The first request may have arrived: look in the queue, and otherwise
      // ask, before anything is sent again.
      if (await notifier.confirmQueued(release)) return;
      if (!context.mounted) return;
      final again = await showDialog<bool>(
        context: context,
        builder: (context) => const _ResendConfirm(),
      );
      if (again ?? false) {
        await notifier.grab(release, confirmedResend: true);
      }
      return;
    }
    if (!release.isRejected) {
      await notifier.grab(release);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RejectedConfirm(reasons: release.rejections),
    );
    if (confirmed ?? false) {
      await notifier.grab(release, confirmedRejected: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = ref.watch(releaseViewProvider(target));
    final grabs = ref.watch(releaseGrabProvider(target));
    final shown = applyReleaseView(all, view);
    final labels = releaseRowLabels(l10n);
    final controls = ReleaseControls<ReleaseSort>(
      labels: ReleaseControlsLabels(
        sortButton: l10n.sonarrReleaseSortButton(_sortLabel(l10n, view.sort)),
        reverseSort: l10n.sonarrReleaseReverseSort,
        filterButton: l10n.sonarrReleaseFilters(view.activeFilters),
        clearFilters: l10n.sonarrReleaseClearFilters,
      ),
      sortOptions: [
        for (final s in ReleaseSort.values)
          ReleaseSortOption(s, _sortLabel(l10n, s)),
      ],
      selectedSort: view.sort,
      onSort: (s) => ref
          .read(releaseViewProvider(target).notifier)
          .update((v) => v.copyWith(sort: s, reversed: false)),
      onReverse: () => ref
          .read(releaseViewProvider(target).notifier)
          .update((v) => v.copyWith(reversed: !v.reversed)),
      groups: _groups(l10n, view),
      activeFilters: view.activeFilters,
      onToggleFilter: (g, id) => _toggle(ref, g, id),
      onClearFilters: () =>
          ref.read(releaseViewProvider(target).notifier).clearFilters(),
    );
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.xl,
      ),
      itemCount: shown.length + (shown.isEmpty ? 2 : 1),
      itemBuilder: (context, index) {
        if (index == 0) return controls;
        if (shown.isEmpty) {
          return SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.filter_alt_off,
              headline: l10n.sonarrReleaseNoMatchHeadline,
              message: l10n.sonarrReleaseNoMatchMessage,
              actionLabel: l10n.sonarrReleaseClearFilters,
              onAction: () =>
                  ref.read(releaseViewProvider(target).notifier).clearFilters(),
            ),
          );
        }
        final release = shown[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
          child: ReleaseRow(
            key: ValueKey(grabKey(release)),
            data: releaseRowData(l10n, release, grabs[grabKey(release)]),
            labels: labels,
            onDownload: () => _download(context, ref, release),
          ),
        );
      },
    );
  }
}

class _ResendConfirm extends StatelessWidget {
  const _ResendConfirm();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.sonarrReleaseResendTitle),
      content: Text(l10n.sonarrReleaseResendMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.sonarrReleaseCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.sonarrReleaseResendConfirm),
        ),
      ],
    );
  }
}

class _RejectedConfirm extends StatelessWidget {
  const _RejectedConfirm({required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.sonarrReleaseRejectedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sonarrReleaseRejectedMessage),
            const SizedBox(height: ConsolarrSpacing.sm),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(top: ConsolarrSpacing.xxs),
                child: Text('• $reason'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.sonarrReleaseCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.sonarrReleaseRejectedConfirm),
        ),
      ],
    );
  }
}
