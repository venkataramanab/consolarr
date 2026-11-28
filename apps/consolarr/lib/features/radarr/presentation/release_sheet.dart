// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/queue_row_builder.dart';
import 'package:consolarr/features/arr_common/presentation/release_controls.dart';
import 'package:consolarr/features/arr_common/presentation/release_row.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/release_query.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/shared/l10n/join_parts.dart';
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
    detents: GlassSheetDetents.full,
    // The sheet paints its own surface: tiles need a Material of their own.
    scrollBuilder: (context, controller) => Material(
      type: MaterialType.transparency,
      child: ReleaseSheetBody(movieId: movieId, controller: controller),
    ),
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

/// "5 minutes old", "3 hours old", "4 days old".
String releaseAgeText(AppLocalizations l10n, int minutes) {
  if (minutes < 60) return l10n.radarrReleaseAgeMinutes(minutes);
  if (minutes < 60 * 48) return l10n.radarrReleaseAgeHours(minutes ~/ 60);
  return l10n.radarrReleaseAgeDays(minutes ~/ (60 * 24));
}

ReleaseRowLabels releaseRowLabels(AppLocalizations l10n) => ReleaseRowLabels(
  download: l10n.radarrDownload,
  downloadAgain: l10n.radarrReleaseDownloadAgain,
  grabbing: l10n.radarrGrabbing,
  grabbed: l10n.radarrGrabbed,
  failed: l10n.radarrGrabFailed,
  maybeSent: l10n.radarrReleaseMaybeSent,
  rejectedBadge: l10n.radarrRejectedChip,
  expand: l10n.radarrExpand,
  collapse: l10n.radarrCollapse,
  rejectionsHeading: l10n.radarrRejectionReasons,
  customFormatsHeading: l10n.radarrCustomFormats,
  languagesHeading: l10n.radarrReleaseLanguages,
  partSeparator: l10n.sharedPartSeparator,
);

ReleaseGrabState grabStateOf(GrabPhase? phase) => switch (phase) {
  null => ReleaseGrabState.idle,
  GrabPhase.grabbing => ReleaseGrabState.grabbing,
  GrabPhase.grabbed => ReleaseGrabState.grabbed,
  GrabPhase.failed => ReleaseGrabState.failed,
  GrabPhase.maybeSent => ReleaseGrabState.maybeSent,
};

/// The view-model of one release row.
ReleaseRowData releaseRowData(
  AppLocalizations l10n,
  ArrRelease r,
  GrabPhase? phase,
) {
  final grab = grabStateOf(phase);
  final facts = [
    ?r.qualityName,
    if (r.size > 0) queueSizeText(l10n, r.size),
    releaseAgeText(l10n, r.ageMinutes),
    if (r.seeders != null) l10n.radarrSeeders(r.seeders!),
    ?r.indexer,
  ];
  final stateText = switch (grab) {
    ReleaseGrabState.idle => null,
    ReleaseGrabState.grabbing => l10n.radarrGrabbing,
    ReleaseGrabState.grabbed => l10n.radarrGrabbed,
    ReleaseGrabState.failed => l10n.radarrGrabFailed,
    ReleaseGrabState.maybeSent => l10n.radarrReleaseMaybeSent,
  };
  final details = joinList(l10n, [
    ...facts,
    if (r.isRejected) l10n.radarrRejectedChip,
    ?stateText,
  ]);
  return ReleaseRowData(
    title: r.title,
    facts: facts,
    semanticsLabel: l10n.radarrReleaseSemantics(r.title, details),
    isRejected: r.isRejected,
    rejections: r.rejections,
    customFormats: r.customFormats,
    languages: r.languages,
    grab: grab,
  );
}

const _groupStatus = 'status';
const _groupProtocol = 'protocol';
const _groupResolution = 'resolution';

/// Search field, sort and filter controls, and the result list.
class ReleaseSheetBody extends ConsumerStatefulWidget {
  const ReleaseSheetBody({required this.movieId, this.controller, super.key});

  final int movieId;
  final ScrollController? controller;

  @override
  ConsumerState<ReleaseSheetBody> createState() => _ReleaseSheetBodyState();
}

class _ReleaseSheetBodyState extends ConsumerState<ReleaseSheetBody> {
  ReleaseSortKey _sort = ReleaseSortKey.bestMatch;
  bool _ascending = false;
  ReleaseFilter _filter = const ReleaseFilter();

  /// The result list the grab states were last synced with the queue for.
  List<ArrRelease>? _synced;

  void _retry() => ref.invalidate(releasesProvider(widget.movieId));

  /// A reopened sheet must not offer "Download" for what is queued already.
  void _syncOnce(List<ArrRelease> all) {
    if (identical(_synced, all)) return;
    _synced = all;
    Future<void>.microtask(() async {
      if (!mounted) return;
      await ref
          .read(grabStatusProvider.notifier)
          .syncWithQueue(all, widget.movieId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(releasesProvider(widget.movieId));
    final Widget body;
    // Loading and error first: the previous movie's results must never show.
    if (async.isLoading) {
      body = Semantics(
        label: l10n.radarrSearchingReleases,
        liveRegion: true,
        child: ExcludeSemantics(
          child: ListView.builder(
            controller: widget.controller,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
            itemCount: 5,
            itemBuilder: (_, _) => const Padding(
              padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: SkeletonBox(
                height: 120,
                borderRadius: ConsolarrRadii.card,
              ),
            ),
          ),
        ),
      );
    } else {
      final result = async.hasError ? null : async.value;
      final error = result == null
          ? const AppError(ErrorCategory.parseError)
          : result.errorOrNull;
      if (error != null) {
        body = radarrErrorView(context, error, onRetry: _retry);
      } else {
        final all = result!.valueOrNull!;
        if (all.isEmpty) {
          body = EmptyState(
            icon: Icons.search_off,
            headline: l10n.radarrNoReleasesHeadline,
            message: l10n.radarrNoReleasesMessage,
            actionLabel: l10n.radarrRetry,
            onAction: _retry,
          );
        } else {
          _syncOnce(all);
          body = _list(context, all);
        }
      }
    }
    return RadarrScreenView(
      screen: ScreenName.radarrInteractiveSearch,
      child: body,
    );
  }

  int get _activeFilters =>
      (_filter.acceptance == ReleaseAcceptance.all ? 0 : 1) +
      (_filter.protocol == null ? 0 : 1) +
      (_filter.resolution == null ? 0 : 1);

  List<ReleaseFilterGroup> _groups(AppLocalizations l10n) => [
    ReleaseFilterGroup(
      id: _groupStatus,
      label: l10n.radarrReleaseGroupStatus,
      options: [
        ReleaseFilterOption(
          id: ReleaseAcceptance.accepted.name,
          label: l10n.radarrReleaseAccepted,
          selected: _filter.acceptance == ReleaseAcceptance.accepted,
        ),
        ReleaseFilterOption(
          id: ReleaseAcceptance.rejected.name,
          label: l10n.radarrReleaseRejected,
          selected: _filter.acceptance == ReleaseAcceptance.rejected,
        ),
      ],
    ),
    ReleaseFilterGroup(
      id: _groupProtocol,
      label: l10n.radarrReleaseGroupProtocol,
      options: [
        ReleaseFilterOption(
          id: 'torrent',
          label: l10n.radarrProtocolTorrent,
          selected: _filter.protocol == 'torrent',
        ),
        ReleaseFilterOption(
          id: 'usenet',
          label: l10n.radarrProtocolUsenet,
          selected: _filter.protocol == 'usenet',
        ),
      ],
    ),
    ReleaseFilterGroup(
      id: _groupResolution,
      label: l10n.radarrReleaseGroupResolution,
      options: [
        for (final r in const [2160, 1080, 720])
          ReleaseFilterOption(
            id: '$r',
            label: l10n.radarrResolution(l10n.plainInt(r)),
            selected: _filter.resolution == r,
          ),
      ],
    ),
  ];

  void _toggle(String group, String id) => setState(() {
    switch (group) {
      case _groupStatus:
        final a = ReleaseAcceptance.values.byName(id);
        _filter = _filter.copyWith(
          acceptance: _filter.acceptance == a ? ReleaseAcceptance.all : a,
        );
      case _groupProtocol:
        _filter = _filter.copyWith(
          protocol: _filter.protocol == id ? null : id,
        );
      default:
        final r = int.parse(id);
        _filter = _filter.copyWith(
          resolution: _filter.resolution == r ? null : r,
        );
    }
  });

  void _clear() => setState(
    () => _filter = _filter.copyWith(
      acceptance: ReleaseAcceptance.all,
      protocol: null,
      resolution: null,
    ),
  );

  Widget _list(BuildContext context, List<ArrRelease> all) {
    final l10n = context.l10n;
    final grabs = ref.watch(grabStatusProvider);
    final shown = applyReleaseQuery(all, _sort, _filter, ascending: _ascending);
    final labels = releaseRowLabels(l10n);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: l10n.radarrReleaseSearchHint,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _filter = _filter.copyWith(text: v)),
        ),
        ReleaseControls<ReleaseSortKey>(
          labels: ReleaseControlsLabels(
            sortButton: l10n.radarrReleaseSortedBy(sortText(l10n, _sort)),
            reverseSort: l10n.radarrReleaseReverseSort,
            filterButton: l10n.radarrReleaseFilters(_activeFilters),
            clearFilters: l10n.radarrClearFilters,
          ),
          sortOptions: [
            for (final k in ReleaseSortKey.values)
              ReleaseSortOption(k, sortText(l10n, k)),
          ],
          selectedSort: _sort,
          onSort: (k) => setState(() {
            _sort = k;
            _ascending = false;
          }),
          onReverse: () => setState(() => _ascending = !_ascending),
          groups: _groups(l10n),
          activeFilters: _activeFilters,
          onToggleFilter: _toggle,
          onClearFilters: _clear,
        ),
      ],
    );
    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.xl,
      ),
      itemCount: shown.length + (shown.isEmpty ? 2 : 1),
      itemBuilder: (context, index) {
        if (index == 0) return header;
        if (shown.isEmpty) {
          return SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.filter_alt_off_outlined,
              headline: l10n.radarrNoReleaseMatchHeadline,
              message: l10n.radarrNoReleaseMatchMessage,
              actionLabel: l10n.radarrClearFilters,
              onAction: () => setState(() => _filter = const ReleaseFilter()),
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
            onDownload: () => _download(context, release),
          ),
        );
      },
    );
  }

  Future<void> _download(BuildContext context, ArrRelease release) async {
    final notifier = ref.read(grabStatusProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final queuedText = context.l10n.radarrReleaseAlreadyQueued;
    if (ref.read(grabStatusProvider)[grabKey(release)] == GrabPhase.maybeSent) {
      // The first request may have arrived: look in the queue, and otherwise
      // ask, before anything is sent again.
      if (await notifier.confirmQueued(release, widget.movieId)) {
        messenger?.showSnackBar(SnackBar(content: Text(queuedText)));
        return;
      }
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
    if (release.isRejected) {
      final ok = await confirmRejectedGrab(context, release);
      if (ok != true) return;
    }
    await notifier.grab(release);
  }
}

class _ResendConfirm extends StatelessWidget {
  const _ResendConfirm();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.radarrReleaseResendTitle),
      content: Text(l10n.radarrReleaseResendMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.radarrCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.radarrReleaseResendConfirm),
        ),
      ],
    );
  }
}

/// Rejected releases need a confirmation that shows the reasons.
Future<bool?> confirmRejectedGrab(BuildContext context, ArrRelease release) {
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
                child: Text(l10n.radarrReasonLine(reason)),
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
