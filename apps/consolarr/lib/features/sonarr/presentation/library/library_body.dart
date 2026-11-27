// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/arr_common/presentation/sort_filter_chip_bar.dart';
import 'package:consolarr/features/sonarr/application/library_providers.dart';
import 'package:consolarr/features/sonarr/application/library_query.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/error_messages.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/library/library_filters.dart';
import 'package:consolarr/features/sonarr/presentation/series_views.dart';
import 'package:consolarr/features/sonarr/presentation/stand_ins/filter_sheet.dart';
import 'package:consolarr/features/sonarr/presentation/stand_ins/glass_sheet.dart';
import 'package:consolarr/features/sonarr/presentation/stand_ins/sort_sheet.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Estimated height of a section header and of a list row, used to land near
/// a section before it is built (the exact position is then corrected).
const _headerExtent = 40.0;
const _listRowExtent = 96.0;

/// The series library body (SON-01..05, SON-30): search, sort/filter bar,
/// grouped grid or list, and every state: loading, no server, error per
/// category, empty, filter-empty, no match, partial and offline.
class LibraryBody extends ConsumerStatefulWidget {
  const LibraryBody({
    required this.padding,
    required this.onOpenServers,
    super.key,
  });

  final EdgeInsets padding;
  final void Function(BuildContext context) onOpenServers;

  @override
  ConsumerState<LibraryBody> createState() => _LibraryBodyState();
}

class _LibraryBodyState extends ConsumerState<LibraryBody> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _headerKeys = {};

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(seriesLibraryProvider.notifier).refresh();

  Widget _withRefresh(Widget child) =>
      RefreshIndicator(edgeOffset: 0, onRefresh: _refresh, child: child);

  Widget _statePane(Widget child) => _withRefresh(
    Padding(
      padding: EdgeInsets.only(
        top: widget.padding.top,
        bottom: widget.padding.bottom,
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mode = ref.watch(viewModeProvider);
    final library = ref.watch(seriesLibraryProvider);
    ref.listen(libraryQueryProvider.select((q) => q.search), (_, text) {
      if (_search.text != text) _search.text = text;
    });

    // Order matters: Riverpod keeps the previous value through a reload and
    // through an error, so `value` alone would show the previous server's
    // library as current after a switch.
    final state = library.isLoading || library.hasError ? null : library.value;
    if (state == null) {
      if (library.hasError && !library.isLoading) {
        final copy = sonarrUnexpectedErrorCopy(l10n);
        return _statePane(
          ErrorState(
            headline: copy.title,
            message: copy.message,
            hint: copy.hint,
            retryLabel: l10n.sonarrRetry,
            onRetry: _refresh,
          ),
        );
      }
      return SeriesSkeleton(mode: mode, padding: widget.padding);
    }
    return switch (state) {
      LibraryNoServer() => _statePane(
        EmptyState(
          icon: Icons.dns_outlined,
          headline: l10n.sonarrNoServerHeadline,
          message: l10n.sonarrNoServerMessage,
          actionLabel: l10n.sonarrNoServerAction,
          onAction: () => widget.onOpenServers(context),
        ),
      ),
      LibraryFailure(:final error) => _statePane(_errorState(l10n, error)),
      LibraryData(:final isEmpty) =>
        isEmpty && !state.isOffline
            ? _statePane(
                EmptyState(
                  icon: Icons.tv_outlined,
                  headline: l10n.sonarrEmptyHeadline,
                  message: l10n.sonarrEmptyMessage,
                  actionLabel: l10n.sonarrEmptyAction,
                  onAction: () => _openAdd(context),
                ),
              )
            : _content(context, state, mode),
    };
  }

  void _openAdd(BuildContext context, {String? term}) =>
      GoRouter.maybeOf(context)?.push(sonarrAddLocation(term: term));

  Widget _errorState(AppLocalizations l10n, AppError error) {
    final copy = sonarrErrorCopy(l10n, error);
    return ErrorState(
      headline: copy.title,
      message: copy.message,
      hint: copy.hint,
      retryLabel: l10n.sonarrRetry,
      onRetry: _refresh,
      secondaryLabel: copy.fixedInServerSettings
          ? l10n.sonarrOpenServers
          : null,
      onSecondary: copy.fixedInServerSettings
          ? () => widget.onOpenServers(context)
          : null,
    );
  }

  Widget _content(
    BuildContext context,
    LibraryData data,
    LibraryViewMode mode,
  ) {
    final l10n = context.l10n;
    final padding = widget.padding;
    final source = ref.watch(artworkSourceProvider);
    final now = ref.watch(clockProvider)();
    final query = ref.watch(libraryQueryProvider);
    final visible = ref.watch(visibleSeriesProvider);
    final lookups =
        ref.watch(libraryLookupsProvider).value ?? const LibraryLookups();
    final snapshot = data.snapshot;
    final side = EdgeInsets.only(left: padding.left, right: padding.right);
    final groups = visible.groups;
    _headerKeys.removeWhere((i, _) => i >= groups.length);

    Widget header() => Padding(
      padding: side.copyWith(bottom: ConsolarrSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.sonarrLibrarySearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.sonarrLibrarySearchClear,
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              ref
                                  .read(libraryQueryProvider.notifier)
                                  .setSearch('');
                            },
                          ),
                  ),
                  onChanged: ref.read(libraryQueryProvider.notifier).setSearch,
                ),
              ),
              if (groups.length > 1)
                IconButton(
                  tooltip: l10n.sonarrLibraryJumpTooltip,
                  icon: const Icon(Icons.format_list_bulleted),
                  onPressed: () => _jump(context, groups, mode),
                ),
            ],
          ),
          const SizedBox(height: ConsolarrSpacing.sm),
          ArrSortFilterBar(
            sortLabel: l10n.sonarrLibrarySortChip(
              sortKeyLabel(l10n, query.sortKey),
            ),
            sortSemanticsLabel: l10n.sonarrLibrarySortChipSemantics(
              sortKeyLabel(l10n, query.sortKey),
              query.ascending
                  ? l10n.sonarrLibrarySortAscending
                  : l10n.sonarrLibrarySortDescending,
            ),
            ascending: query.ascending,
            onSort: () => _openSort(context, query),
            filterLabel: l10n.sonarrLibraryFilterChip(query.filter.activeCount),
            filterSemanticsLabel: l10n.sonarrLibraryFilterChipSemantics(
              query.filter.activeCount,
            ),
            onFilter: () => _openFilter(context, query, lookups),
            activeFilters: activeFilters(l10n, query.filter, lookups),
            onRemoveFilter: (id) => ref
                .read(libraryQueryProvider.notifier)
                .applyFilter(removeFilter(query.filter, id)),
            clearAllLabel: l10n.sonarrLibraryFilterClearAll,
            onClearAll: ref.read(libraryQueryProvider.notifier).clearFilter,
          ),
          if (visible.computing)
            Semantics(
              liveRegion: true,
              label: l10n.sonarrLibraryComputing,
              child: const Padding(
                padding: EdgeInsets.only(top: ConsolarrSpacing.xs),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
        ],
      ),
    );

    final slivers = <Widget>[
      if (data.isOffline)
        SliverPadding(
          padding: side.copyWith(bottom: ConsolarrSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: OfflineBanner(
              message: l10n.sonarrOfflineMessage,
              ageText: l10n.sonarrUpdatedAgo(
                ageText(l10n, now.difference(snapshot.fetchedAt)),
              ),
              retryLabel: l10n.sonarrRetry,
              onRetry: _refresh,
            ),
          ),
        ),
      if (data.isPartial)
        SliverPadding(
          padding: side.copyWith(bottom: ConsolarrSpacing.sm),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined),
                  const SizedBox(width: ConsolarrSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.sonarrLibraryPartialBanner(snapshot.skipped),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(child: header()),
      if (visible.count == 0 && !visible.computing)
        SliverFillRemaining(
          hasScrollBody: true,
          child: _emptyResult(context, query, data.snapshot.series.isEmpty),
        )
      else
        for (var i = 0; i < groups.length; i++)
          SliverMainAxisGroup(
            slivers: [
              PinnedHeaderSliver(
                child: _GroupHeader(
                  key: _headerKeys.putIfAbsent(i, GlobalKey.new),
                  label: groupLabel(l10n, groups[i].key),
                ),
              ),
              SliverPadding(
                padding: side.copyWith(bottom: ConsolarrSpacing.sm),
                sliver: mode == LibraryViewMode.grid
                    ? SeriesGridSliver(
                        series: groups[i].series,
                        source: source,
                        now: now,
                      )
                    : SeriesListSliver(
                        series: groups[i].series,
                        source: source,
                        now: now,
                      ),
              ),
            ],
          ),
      SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
    ];

    // The scroll view sits below the top bar (not under it) so the pinned
    // section headers stop at the bar instead of hiding behind it; content
    // still paints over the bar's area while scrolling.
    return Padding(
      padding: EdgeInsets.only(top: padding.top),
      child: _withRefresh(
        CustomScrollView(
          controller: _scroll,
          clipBehavior: Clip.none,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        ),
      ),
    );
  }

  Widget _emptyResult(
    BuildContext context,
    LibraryQuery query,
    bool libraryIsEmpty,
  ) {
    final l10n = context.l10n;
    if (libraryIsEmpty) {
      return EmptyState(
        icon: Icons.tv_outlined,
        headline: l10n.sonarrEmptyHeadline,
        message: l10n.sonarrEmptyMessage,
        actionLabel: l10n.sonarrEmptyAction,
        onAction: () => _openAdd(context),
      );
    }
    final term = query.search.trim();
    if (term.isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        headline: l10n.sonarrLibraryNoMatchHeadline(term),
        message: l10n.sonarrLibraryNoMatchMessage,
        actionLabel: l10n.sonarrLibraryNoMatchAction(term),
        onAction: () => _openAdd(context, term: term),
      );
    }
    return EmptyState(
      icon: Icons.filter_list_off,
      headline: l10n.sonarrLibraryFilterEmptyHeadline,
      message: l10n.sonarrLibraryFilterEmptyMessage,
      actionLabel: l10n.sonarrLibraryFilterEmptyAction,
      onAction: ref.read(libraryQueryProvider.notifier).clearFilter,
    );
  }

  Future<void> _openSort(BuildContext context, LibraryQuery query) {
    final l10n = context.l10n;
    return showGlassSheet<void>(
      context: context,
      title: l10n.sonarrLibrarySortSheetTitle,
      closeLabel: l10n.sonarrLibraryClose,
      builder: (sheetContext, controller) => SortSheet<SeriesSortKey>(
        title: l10n.sonarrLibrarySortSheetTitle,
        options: sortOptions(l10n),
        selected: query.sortKey,
        ascending: query.ascending,
        ascendingLabel: l10n.sonarrLibrarySortAscending,
        descendingLabel: l10n.sonarrLibrarySortDescending,
        saveAsDefaultLabel: l10n.sonarrLibrarySaveDefault,
        applyLabel: l10n.sonarrLibraryApply,
        onApply: (key, ascending, save) {
          ref
              .read(libraryQueryProvider.notifier)
              .applySort(key, ascending: ascending, saveAsDefault: save);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<void> _openFilter(
    BuildContext context,
    LibraryQuery query,
    LibraryLookups lookups,
  ) {
    final l10n = context.l10n;
    return showGlassSheet<void>(
      context: context,
      title: l10n.sonarrLibraryFilterSheetTitle,
      closeLabel: l10n.sonarrLibraryClose,
      builder: (sheetContext, controller) => FilterSheet(
        title: l10n.sonarrLibraryFilterSheetTitle,
        sections: filterSections(l10n, query.filter, lookups),
        activeCount: query.filter.activeCount,
        clearAllLabel: l10n.sonarrLibraryFilterClearAll,
        saveAsDefaultLabel: l10n.sonarrLibrarySaveDefault,
        applyLabel: l10n.sonarrLibraryApply,
        onApply: (selection, save) {
          ref
              .read(libraryQueryProvider.notifier)
              .applyFilter(filterFromSelection(selection), saveAsDefault: save);
          Navigator.of(sheetContext).pop();
        },
        onClear: () {
          ref.read(libraryQueryProvider.notifier).clearFilter();
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<void> _jump(
    BuildContext context,
    List<SeriesGroup> groups,
    LibraryViewMode mode,
  ) async {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width - widget.padding.horizontal;
    final columns = (width / (posterMaxExtent + ConsolarrSpacing.sm))
        .ceil()
        .clamp(1, 12);
    final cell = (width - (columns - 1) * ConsolarrSpacing.sm) / columns;
    final rowExtent = mode == LibraryViewMode.grid
        ? cell * 3 / 2 + ConsolarrSpacing.sm
        : _listRowExtent;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final index = await showGlassSheet<int>(
      context: context,
      title: l10n.sonarrLibraryJumpTitle,
      closeLabel: l10n.sonarrLibraryClose,
      builder: (sheetContext, controller) => ListView.builder(
        controller: controller,
        itemCount: groups.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(groupLabel(l10n, groups[i].key)),
          onTap: () => Navigator.of(sheetContext).pop(i),
        ),
      ),
    );
    if (index == null || !mounted || !_scroll.hasClients) return;
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      final n = groups[i].series.length;
      final rows = mode == LibraryViewMode.grid ? (n / columns).ceil() : n;
      offset +=
          _headerExtent * scale +
          rows * rowExtent * (mode == LibraryViewMode.grid ? 1 : scale);
    }
    _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final ctx = _headerKeys[index]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0);
        return;
      }
    }
  }
}

/// A pinned section header.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: context.l10n.sonarrLibraryGroupHeaderSemantics(label),
      excludeSemantics: true,
      child: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(
          horizontal: ConsolarrSpacing.lg,
          vertical: ConsolarrSpacing.xs,
        ),
        color: context.roles.page,
        child: Text(
          label,
          style: theme.textTheme.labelLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
