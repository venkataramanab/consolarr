// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/sort_filter_chip_bar.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

String sortKeyText(AppLocalizations l10n, MovieSortKey k) => switch (k) {
  MovieSortKey.title => l10n.radarrSortTitleKey,
  MovieSortKey.year => l10n.radarrSortYear,
  MovieSortKey.added => l10n.radarrSortAdded,
  MovieSortKey.downloaded => l10n.radarrSortDownloaded,
  MovieSortKey.theatrical => l10n.radarrSortTheatrical,
  MovieSortKey.digital => l10n.radarrSortDigital,
  MovieSortKey.size => l10n.radarrSortSize,
  MovieSortKey.rating => l10n.radarrSortRating,
  MovieSortKey.popularity => l10n.radarrSortPopularity,
  MovieSortKey.qualityProfile => l10n.radarrSortProfile,
  MovieSortKey.genre => l10n.radarrSortGenre,
};

/// How long the library search waits after the last keystroke.
const searchDebounce = Duration(milliseconds: 150);

/// The movie library (RAD-01..05): toolbar, groups with a jump control and
/// every state (loading, data, empty, no match, filter-empty, error, offline).
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({required this.padding, super.key});

  final EdgeInsets padding;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  /// Applies the typed text after a short pause, so a big library is not
  /// filtered on every keystroke.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      if (mounted) ref.read(libraryQueryProvider.notifier).setSearch(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    ref.read(libraryQueryProvider.notifier).setSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref.read(movieLibraryProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final library = ref.watch(movieLibraryProvider);
    final mode = ref.watch(viewModeProvider);

    Widget pane(Widget child) => RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: padding.left,
            right: padding.right,
            bottom: padding.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: c.maxHeight - padding.bottom,
            ),
            child: child,
          ),
        ),
      ),
    );

    // Order matters: Riverpod keeps the previous value through a reload and
    // through an error (a server switch would show the old server's data).
    if (library.isLoading) return MovieSkeleton(mode: mode, padding: padding);
    if (library.hasError) {
      return pane(
        radarrErrorView(
          context,
          const AppError(ErrorCategory.parseError),
          onRetry: _refresh,
        ),
      );
    }
    final state = library.value;
    return switch (state) {
      null => MovieSkeleton(mode: mode, padding: padding),
      RadarrNoServer() => pane(radarrNoServerView(context)),
      RadarrGone() => pane(radarrNoServerView(context)),
      RadarrFailure(:final error) => pane(
        radarrErrorView(context, error, onRetry: _refresh),
      ),
      RadarrData(:final snapshot) => _content(context, snapshot, mode),
    };
  }

  Widget _content(
    BuildContext context,
    Snapshot<List<RadarrMovie>> snapshot,
    LibraryViewMode mode,
  ) {
    final l10n = context.l10n;
    final padding = widget.padding;
    final query = ref.watch(libraryQueryProvider);
    final visibleState = ref.watch(visibleMoviesProvider);
    final visible = visibleState.movies;
    final source = ref.watch(artworkSourceProvider);
    final now = ref.watch(clockProvider)();
    final groups = visibleState.groups;
    final offline = snapshot.isOffline;

    Widget? empty;
    if (snapshot.value.isEmpty && !offline) {
      empty = EmptyState(
        icon: Icons.movie_outlined,
        headline: l10n.radarrEmptyHeadline,
        message: l10n.radarrEmptyMessage,
        actionLabel: l10n.radarrAddMovie,
        onAction: () => openAddMovie(context),
      );
    } else if (visible.isEmpty && query.search.trim().isNotEmpty) {
      empty = EmptyState(
        icon: Icons.search_off,
        headline: l10n.radarrNoMatchHeadline,
        message: l10n.radarrNoMatchMessage,
        actionLabel: l10n.radarrSearchToAdd,
        onAction: () => openAddMovie(context, term: query.search.trim()),
      );
    } else if (visible.isEmpty) {
      empty = EmptyState(
        icon: Icons.filter_alt_off_outlined,
        headline: l10n.radarrFilterEmptyHeadline,
        message: l10n.radarrFilterEmptyMessage,
        actionLabel: l10n.radarrClearFilters,
        onAction: () =>
            ref.read(libraryQueryProvider.notifier).setFilter(MovieFilter.none),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth - padding.left - padding.right;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          return CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  left: padding.left,
                  right: padding.right,
                  top: padding.top,
                ),
                sliver: SliverList.list(
                  children: [
                    if (offline)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: ConsolarrSpacing.sm,
                        ),
                        child: offlineBanner(
                          context,
                          fetchedAt: snapshot.fetchedAt,
                          now: now,
                          onRetry: _refresh,
                        ),
                      ),
                    _Toolbar(
                      controller: _search,
                      groups: groups,
                      computing: visibleState.computing,
                      onSearchChanged: _onSearchChanged,
                      onClearSearch: _clearSearch,
                      onJump: (index) => _jump(
                        groups,
                        index,
                        mode == LibraryViewMode.grid,
                        width,
                        scale,
                      ),
                    ),
                  ],
                ),
              ),
              if (empty != null)
                SliverFillRemaining(child: empty)
              else
                SliverPadding(
                  padding: EdgeInsets.only(
                    left: padding.left,
                    right: padding.right,
                    bottom: padding.bottom,
                  ),
                  sliver: MovieGroupsSliver(
                    groups: groups,
                    grid: mode == LibraryViewMode.grid,
                    source: source,
                    now: now,
                    onOpen: (m) => openMovie(context, m.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _jump(
    List<MovieGroup> groups,
    int index,
    bool grid,
    double width,
    double scale,
  ) {
    final offsets = groupOffsets(
      groups,
      grid: grid,
      width: width,
      textScale: scale,
    );
    if (!_scroll.hasClients) return;
    final target = offsets[index].clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.controller,
    required this.groups,
    required this.computing,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onJump,
  });

  final TextEditingController controller;
  final List<MovieGroup> groups;
  final bool computing;
  final void Function(String value) onSearchChanged;
  final VoidCallback onClearSearch;
  final void Function(int index) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(libraryQueryProvider);
    final mode = ref.watch(viewModeProvider);
    final profiles = ref.watch(qualityProfilesProvider);
    final tags = ref.watch(tagsProvider);
    final isGrid = mode == LibraryViewMode.grid;
    final canJump = groups.length > 1 && groups.first.label.isNotEmpty;
    final names = <int, String>{for (final p in profiles.value ?? const []) p.id: p.name};
    final tagNames = <int, String>{for (final t in tags.value ?? const []) t.id: t.label};
    final sortName = sortKeyText(l10n, query.sort);
    final direction = query.ascending
        ? l10n.radarrAscending
        : l10n.radarrDescending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.radarrSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.radarrClearSearch,
                            icon: const Icon(Icons.close),
                            onPressed: onClearSearch,
                          ),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
            ),
            IconButton(
              tooltip: isGrid
                  ? l10n.radarrSwitchToList
                  : l10n.radarrSwitchToGrid,
              icon: Icon(isGrid ? Icons.view_list_outlined : Icons.grid_view),
              onPressed: () => ref
                  .read(viewModeProvider.notifier)
                  .set(isGrid ? LibraryViewMode.list : LibraryViewMode.grid),
            ),
            if (canJump)
              IconButton(
                tooltip: l10n.radarrJumpAction,
                icon: const Icon(Icons.vertical_align_top),
                onPressed: () => _showJump(context),
              ),
          ],
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        ArrSortFilterBar(
          sortLabel: l10n.radarrSortChip(sortName),
          sortSemanticsLabel: l10n.radarrSortChipSemantics(sortName, direction),
          ascending: query.ascending,
          onSort: () => _showSort(context, ref, query),
          filterLabel: l10n.radarrFilterChip(query.filter.activeCount),
          filterSemanticsLabel: l10n.radarrFilterChipSemantics(
            query.filter.activeCount,
          ),
          onFilter: () => _showFilter(context, ref, query),
          activeFilters: [
            for (final id in activeFilterIds(query.filter))
              ArrActiveFilter(
                id: id,
                label: filterChipText(l10n, id, names, tagNames),
                removeLabel: l10n.radarrFilterRemoveNamed(
                  filterChipText(l10n, id, names, tagNames),
                ),
              ),
          ],
          onRemoveFilter: (id) => ref
              .read(libraryQueryProvider.notifier)
              .setFilter(removeFilter(query.filter, id)),
          clearAllLabel: l10n.radarrClearFilters,
          onClearAll: () => ref
              .read(libraryQueryProvider.notifier)
              .setFilter(MovieFilter.none),
        ),
        if (profiles.hasError || tags.hasError)
          Padding(
            padding: const EdgeInsets.only(top: ConsolarrSpacing.xs),
            child: Semantics(
              container: true,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined),
                  const SizedBox(width: ConsolarrSpacing.sm),
                  Expanded(child: Text(l10n.radarrProfilesFailed)),
                  TextButton(
                    onPressed: () {
                      ref
                        ..invalidate(qualityProfilesProvider)
                        ..invalidate(tagsProvider);
                    },
                    child: Text(l10n.radarrRetry),
                  ),
                ],
              ),
            ),
          ),
        if (computing)
          Semantics(
            liveRegion: true,
            label: l10n.radarrLibraryComputing,
            child: const Padding(
              padding: EdgeInsets.only(top: ConsolarrSpacing.xs),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ),
      ],
    );
  }

  void _showJump(BuildContext context) {
    final l10n = context.l10n;
    showGlassSheet<void>(
      context: context,
      title: l10n.radarrJumpTitle,
      closeLabel: l10n.radarrClose,
      detents: GlassSheetDetents.full,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
        child: Wrap(
          spacing: ConsolarrSpacing.sm,
          children: [
            for (var i = 0; i < groups.length; i++)
              ActionChip(
                label: Text(groups[i].label),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () {
                  Navigator.of(sheet).pop();
                  onJump(i);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSort(BuildContext context, WidgetRef ref, MovieQuery query) {
    final l10n = context.l10n;
    showGlassSheet<void>(
      context: context,
      title: l10n.radarrSortSheetTitle,
      closeLabel: l10n.radarrClose,
      detents: GlassSheetDetents.full,
      builder: (sheet) => SortSheet<MovieSortKey>(
        title: l10n.radarrSortSheetTitle,
        options: [
          for (final k in MovieSortKey.values)
            SortOption(key: k, label: sortKeyText(l10n, k)),
        ],
        selected: query.sort,
        ascending: query.ascending,
        ascendingLabel: l10n.radarrAscending,
        descendingLabel: l10n.radarrDescending,
        saveAsDefaultLabel: l10n.radarrSaveAsDefault,
        applyLabel: l10n.radarrApply,
        onApply: (key, asc, save) {
          Navigator.of(sheet).pop();
          ref
              .read(libraryQueryProvider.notifier)
              .setSort(key, ascending: asc, saveAsDefault: save);
        },
      ),
    );
  }

  void _showFilter(BuildContext context, WidgetRef ref, MovieQuery query) {
    final l10n = context.l10n;
    final profiles = ref.read(qualityProfilesProvider).value ?? const [];
    final tags = ref.read(tagsProvider).value ?? const [];
    final library = ref.read(movieLibraryProvider).value;
    final collections = <String>{
      if (library is RadarrData<List<RadarrMovie>>)
        for (final m in library.value)
          if (m.collectionTitle != null) m.collectionTitle!,
    }.toList()..sort();
    final f = query.filter;
    showGlassSheet<void>(
      context: context,
      title: l10n.radarrFilterSheetTitle,
      closeLabel: l10n.radarrClose,
      detents: GlassSheetDetents.full,
      builder: (sheet) => FilterSheet(
        title: l10n.radarrFilterSheetTitle,
        activeCount: f.activeCount,
        activeCountLabel: l10n.radarrFilterChip(f.activeCount),
        clearAllLabel: l10n.radarrClearFilters,
        saveAsDefaultLabel: l10n.radarrSaveAsDefault,
        applyLabel: l10n.radarrApply,
        sections: [
          FilterSection(
            id: 'monitored',
            label: l10n.radarrFilterMonitored,
            chips: [
              FilterChoice(id: 'monitored', label: l10n.radarrMonitored),
              FilterChoice(id: 'unmonitored', label: l10n.radarrUnmonitored),
            ],
          ),
          FilterSection(
            id: 'file',
            label: l10n.radarrFilterFile,
            chips: [
              FilterChoice(id: 'downloaded', label: l10n.radarrDownloaded),
              FilterChoice(id: 'missing', label: l10n.radarrMissing),
            ],
          ),
          FilterSection(
            id: 'availability',
            label: l10n.radarrFilterAvailability,
            multiSelect: true,
            chips: [
              for (final m in MinimumAvailability.values)
                if (m != MinimumAvailability.unknown)
                  FilterChoice(
                    id: m.name,
                    label: minimumAvailabilityText(l10n, m),
                  ),
            ],
          ),
          if (profiles.isNotEmpty)
            FilterSection(
              id: 'profile',
              label: l10n.radarrFilterProfile,
              multiSelect: true,
              chips: [
                for (final p in profiles)
                  FilterChoice(id: '${p.id}', label: p.name),
              ],
            ),
          if (tags.isNotEmpty)
            FilterSection(
              id: 'tag',
              label: l10n.radarrFilterTags,
              multiSelect: true,
              chips: [
                for (final t in tags)
                  FilterChoice(id: '${t.id}', label: t.label),
              ],
            ),
          if (collections.isNotEmpty)
            FilterSection(
              id: 'collection',
              label: l10n.radarrFilterCollection,
              multiSelect: true,
              chips: [
                for (final c in collections) FilterChoice(id: c, label: c),
              ],
            ),
        ],
        selection: filterSelection(f),
        onClear: () {
          Navigator.of(sheet).pop();
          ref.read(libraryQueryProvider.notifier).setFilter(MovieFilter.none);
        },
        onApply: (sel, save) {
          Navigator.of(sheet).pop();
          ref
              .read(libraryQueryProvider.notifier)
              .setFilter(filterFromSelection(sel), saveAsDefault: save);
        },
      ),
    );
  }
}

/// The text of an active-filter chip ([id] as in `activeFilterIds`).
String filterChipText(
  AppLocalizations l10n,
  String id,
  Map<int, String> profileNames,
  Map<int, String> tagNames,
) {
  final colon = id.indexOf(':');
  final kind = colon < 0 ? id : id.substring(0, colon);
  final value = colon < 0 ? '' : id.substring(colon + 1);
  return switch (kind) {
    'monitored' => l10n.radarrFilterMonitored,
    'file' => l10n.radarrFilterFile,
    'availability' => minimumAvailabilityText(
      l10n,
      MinimumAvailability.values.firstWhere(
        (m) => m.name == value,
        orElse: () => MinimumAvailability.unknown,
      ),
    ),
    'profile' =>
      profileNames[int.tryParse(value)] ??
          l10n.radarrFilterProfileFallback(int.tryParse(value) ?? 0),
    'tag' => tagNames[int.tryParse(value)] ?? value,
    'collection' => value,
    _ => '',
  };
}

/// The chip state of the filter sheet for [f].
FilterSelection filterSelection(MovieFilter f) => FilterSelection({
  'monitored': {
    if (f.monitored == MonitoredFilter.monitored) 'monitored',
    if (f.monitored == MonitoredFilter.unmonitored) 'unmonitored',
  },
  'file': {
    if (f.file == FileFilter.downloaded) 'downloaded',
    if (f.file == FileFilter.missing) 'missing',
  },
  'availability': {for (final a in f.availability) a.name},
  'profile': {for (final p in f.qualityProfiles) '$p'},
  'tag': {for (final t in f.tags) '$t'},
  'collection': {...f.collections},
});

/// The filter a sheet selection stands for.
MovieFilter filterFromSelection(FilterSelection sel) => MovieFilter(
  monitored: sel.of('monitored').contains('monitored')
      ? MonitoredFilter.monitored
      : sel.of('monitored').contains('unmonitored')
      ? MonitoredFilter.unmonitored
      : MonitoredFilter.any,
  file: sel.of('file').contains('downloaded')
      ? FileFilter.downloaded
      : sel.of('file').contains('missing')
      ? FileFilter.missing
      : FileFilter.any,
  availability: {
    for (final m in MinimumAvailability.values)
      if (sel.of('availability').contains(m.name)) m,
  },
  qualityProfiles: {for (final v in sel.of('profile')) ?int.tryParse(v)},
  tags: {for (final v in sel.of('tag')) ?int.tryParse(v)},
  collections: {...sel.of('collection')},
);
