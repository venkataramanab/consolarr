// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/search_status_button.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/availability.dart';
import 'package:consolarr/features/radarr/domain/wanted.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// The scope selector's state.
final wantedScopeProvider = NotifierProvider<_ScopeNotifier, WantedScope>(
  _ScopeNotifier.new,
);

class _ScopeNotifier extends Notifier<WantedScope> {
  @override
  WantedScope build() => WantedScope.released;
  void set(WantedScope s) => state = s;
}

String scopeText(AppLocalizations l10n, WantedScope s) => switch (s) {
  WantedScope.released => l10n.radarrScopeReleased,
  WantedScope.upcoming => l10n.radarrScopeUpcoming,
  WantedScope.allMissing => l10n.radarrScopeAll,
};

/// Missing and upcoming movies with per-row search and "search all missing".
class MissingPage extends ConsumerWidget {
  const MissingPage({required this.padding, super.key});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(movieLibraryProvider);
    final scope = ref.watch(wantedScopeProvider);
    final now = ref.watch(clockProvider)();
    Future<void> refresh() => ref.read(movieLibraryProvider.notifier).refresh();

    Widget pane(Widget child) => RefreshIndicator(
      onRefresh: refresh,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.maxHeight - padding.vertical,
            ),
            child: child,
          ),
        ),
      ),
    );

    final Widget body;
    if (async.isLoading) {
      body = ListSkeleton(padding: padding);
    } else if (async.hasError || async.value == null) {
      body = pane(
        radarrErrorView(
          context,
          const AppError(ErrorCategory.parseError),
          onRetry: refresh,
        ),
      );
    } else {
      body = switch (async.value!) {
        RadarrNoServer() || RadarrGone() => pane(radarrNoServerView(context)),
        RadarrFailure(:final error) => pane(
          radarrErrorView(context, error, onRetry: refresh),
        ),
        RadarrData(:final snapshot) => _list(
          context,
          ref,
          snapshot,
          scope,
          now,
          refresh,
          l10n,
        ),
      };
    }
    return RadarrScreenView(screen: ScreenName.radarrMissing, child: body);
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    Snapshot<List<RadarrMovie>> snapshot,
    WantedScope scope,
    DateTime now,
    Future<void> Function() refresh,
    AppLocalizations l10n,
  ) {
    // Computed once per library and scope; scrolling never sorts again.
    final rows = ref.watch(wantedMoviesProvider(scope));
    final allPhase = ref.watch(
      searchPhaseProvider(SearchStatusNotifier.allMissingKey),
    );
    final offline = snapshot.isOffline;
    final allBusy =
        allPhase == SearchPhase.starting ||
        allPhase == SearchPhase.queued ||
        allPhase == SearchPhase.searching;
    final (allText, allIcon) = switch (allPhase) {
      SearchPhase.starting => (
        l10n.radarrSearchStarting,
        Icons.hourglass_empty,
      ),
      SearchPhase.queued => (l10n.radarrSearchQueued, Icons.schedule),
      SearchPhase.searching => (l10n.radarrSearchAllRunning, Icons.search),
      SearchPhase.done => (
        l10n.radarrSearchAllDone,
        Icons.check_circle_outline,
      ),
      SearchPhase.failed => (l10n.radarrSearchFailed, Icons.error_outline),
      SearchPhase.stillRunning => (
        l10n.radarrSearchStillRunning,
        Icons.schedule,
      ),
      null => (null, null),
    };
    // Upcoming movies cannot be found yet: "search all" is not offered there.
    final canSearchAll = scope != WantedScope.upcoming && rows.isNotEmpty;
    final head = <Widget>[
      if (offline)
        Padding(
          padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
          child: offlineBanner(
            context,
            fetchedAt: snapshot.fetchedAt,
            now: now,
            onRetry: refresh,
          ),
        ),
      Wrap(
        spacing: ConsolarrSpacing.sm,
        children: [
          for (final s in WantedScope.values)
            ChoiceChip(
              label: Text(scopeText(l10n, s)),
              selected: s == scope,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => ref.read(wantedScopeProvider.notifier).set(s),
            ),
        ],
      ),
      if (canSearchAll)
        Padding(
          padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: offline || allBusy
                  ? null
                  : () => _confirmAll(context, ref),
              icon: const Icon(Icons.search),
              label: Text(l10n.radarrSearchAllMissing),
            ),
          ),
        ),
      if (allText != null)
        Padding(
          padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
          child: Semantics(
            liveRegion: true,
            child: StatusChip(
              label: allText,
              icon: allIcon!,
              tone: allPhase == SearchPhase.failed
                  ? StatusTone.error
                  : allPhase == SearchPhase.done
                  ? StatusTone.success
                  : StatusTone.info,
            ),
          ),
        ),
    ];
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: head.length + (rows.isEmpty ? 1 : rows.length),
        itemBuilder: (context, i) {
          if (i < head.length) return head[i];
          if (rows.isEmpty) {
            return SizedBox(
              height: 320,
              child: EmptyState(
                icon: Icons.task_alt,
                headline: switch (scope) {
                  WantedScope.upcoming => l10n.radarrUpcomingEmptyHeadline,
                  _ => l10n.radarrMissingEmptyHeadline,
                },
                message: switch (scope) {
                  WantedScope.upcoming => l10n.radarrUpcomingEmptyMessage,
                  _ => l10n.radarrMissingEmptyMessage,
                },
              ),
            );
          }
          final m = rows[i - head.length];
          return Padding(
            padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
            child: _MissingRow(
              key: ValueKey(m.id),
              movie: m,
              now: now,
              offline: offline,
              searchable: scope != WantedScope.upcoming,
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmAll(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.radarrSearchAllTitle),
        content: Text(l10n.radarrSearchAllWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.radarrCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.radarrSearchAllConfirm),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(searchStatusProvider.notifier).searchAllMissing();
    }
  }
}

/// How a search [phase] shows on the shared search control.
ArrSearchStatus searchStatusOf(SearchPhase? phase) => switch (phase) {
  null => ArrSearchStatus.idle,
  SearchPhase.starting ||
  SearchPhase.queued ||
  SearchPhase.searching => ArrSearchStatus.searching,
  SearchPhase.done => ArrSearchStatus.finished,
  SearchPhase.failed => ArrSearchStatus.failed,
  SearchPhase.stillRunning => ArrSearchStatus.stillRunning,
};

/// The localized strings of the shared search control for [title].
ArrSearchLabels searchLabels(AppLocalizations l10n, String title) =>
    ArrSearchLabels(
      search: l10n.radarrSearchMovieNamed(title),
      searching: l10n.radarrSearchRunning,
      grabbed: l10n.radarrSearchDone,
      nothingFound: l10n.radarrSearchDone,
      failed: l10n.radarrSearchFailed,
      retry: l10n.radarrRetry,
      finished: l10n.radarrSearchDone,
      stillRunning: l10n.radarrSearchStillRunning,
    );

class _MissingRow extends ConsumerWidget {
  const _MissingRow({
    required this.movie,
    required this.now,
    required this.offline,
    required this.searchable,
    super.key,
  });

  final RadarrMovie movie;
  final DateTime now;
  final bool offline;
  final bool searchable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Only this row rebuilds when its own search changes.
    final phase = ref.watch(searchPhaseProvider(movie.id));
    final a = availabilityOf(movie, now);
    return MediaListTile(
      title: movie.title,
      metadata: [
        if (movie.year case final year?) l10n.plainInt(year),
        availabilityText(l10n, a),
      ],
      semanticsLabel: l10n.radarrMissingRowSemantics(
        movie.title,
        availabilityText(l10n, a),
      ),
      onTap: () => openMovie(context, movie.id),
      trailing: !searchable
          ? null
          : ArrSearchButton(
              status: searchStatusOf(phase),
              labels: searchLabels(l10n, movie.title),
              enabled: !offline,
              onSearch: () =>
                  ref.read(searchStatusProvider.notifier).searchMovie(movie.id),
            ),
    );
  }
}
