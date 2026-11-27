// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/domain/library_query.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/stand_ins/glass_sheet.dart';
import 'package:consolarr/features/radarr/presentation/stand_ins/sort_filter_sheets.dart';
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

  @override
  void dispose() {
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
    final visible = ref.watch(visibleMoviesProvider);
    final source = ref.watch(artworkSourceProvider);
    final now = ref.watch(clockProvider)();
    final groups = groupMovies(visible, query.sort);
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
    required this.onJump,
  });

  final TextEditingController controller;
  final List<MovieGroup> groups;
  final void Function(int index) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final query = ref.watch(libraryQueryProvider);
    final mode = ref.watch(viewModeProvider);
    final isGrid = mode == LibraryViewMode.grid;
    final canJump = groups.length > 1 && groups.first.label.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.radarrSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.search.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.radarrClearSearch,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      ref.read(libraryQueryProvider.notifier).setSearch('');
                    },
                  ),
          ),
          onChanged: ref.read(libraryQueryProvider.notifier).setSearch,
        ),
        Wrap(
          children: [
            IconButton(
              tooltip: l10n.radarrSortAction,
              icon: const Icon(Icons.sort),
              onPressed: () => _showSort(context, ref, query),
            ),
            IconButton(
              tooltip: query.filter.isActive
                  ? l10n.radarrFilterActive(query.filter.activeCount)
                  : l10n.radarrFilterAction,
              icon: Badge(
                isLabelVisible: query.filter.isActive,
                label: Text('${query.filter.activeCount}'),
                child: const Icon(Icons.filter_list),
              ),
              onPressed: () => _showFilter(context, ref, query),
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
      ],
    );
  }

  void _showJump(BuildContext context) {
    final l10n = context.l10n;
    showGlassSheet<void>(
      context: context,
      title: l10n.radarrJumpTitle,
      closeLabel: l10n.radarrClose,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
        children: [
          Wrap(
            spacing: ConsolarrSpacing.sm,
            children: [
              for (var i = 0; i < groups.length; i++)
                ActionChip(
                  label: Text(groups[i].label),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    onJump(i);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSort(BuildContext context, WidgetRef ref, MovieQuery query) {
    final l10n = context.l10n;
    showGlassSheet<void>(
      context: context,
      title: l10n.radarrSortSheetTitle,
      closeLabel: l10n.radarrClose,
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
      builder: (sheet) => FilterSheet(
        title: l10n.radarrFilterSheetTitle,
        activeCount: f.activeCount,
        clearAllLabel: l10n.radarrClearFilters,
        saveAsDefaultLabel: l10n.radarrSaveAsDefault,
        applyLabel: l10n.radarrApply,
        sections: [
          FilterSection(
            id: 'monitored',
            label: l10n.radarrFilterMonitored,
            chips: [
              FilterChipOption(id: 'monitored', label: l10n.radarrMonitored),
              FilterChipOption(
                id: 'unmonitored',
                label: l10n.radarrUnmonitored,
              ),
            ],
          ),
          FilterSection(
            id: 'file',
            label: l10n.radarrFilterFile,
            chips: [
              FilterChipOption(id: 'downloaded', label: l10n.radarrDownloaded),
              FilterChipOption(id: 'missing', label: l10n.radarrMissing),
            ],
          ),
          FilterSection(
            id: 'availability',
            label: l10n.radarrFilterAvailability,
            multiSelect: true,
            chips: [
              for (final m in MinimumAvailability.values)
                if (m != MinimumAvailability.unknown)
                  FilterChipOption(
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
                  FilterChipOption(id: '${p.id}', label: p.name),
              ],
            ),
          if (tags.isNotEmpty)
            FilterSection(
              id: 'tag',
              label: l10n.radarrFilterTags,
              multiSelect: true,
              chips: [
                for (final t in tags)
                  FilterChipOption(id: '${t.id}', label: t.label),
              ],
            ),
          if (collections.isNotEmpty)
            FilterSection(
              id: 'collection',
              label: l10n.radarrFilterCollection,
              multiSelect: true,
              chips: [
                for (final c in collections) FilterChipOption(id: c, label: c),
              ],
            ),
        ],
        initial: {
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
        },
        onClear: () {
          Navigator.of(sheet).pop();
          ref.read(libraryQueryProvider.notifier).setFilter(MovieFilter.none);
        },
        onApply: (sel, save) {
          Navigator.of(sheet).pop();
          Set<String> s(String id) => sel[id] ?? const {};
          ref
              .read(libraryQueryProvider.notifier)
              .setFilter(
                MovieFilter(
                  monitored: s('monitored').contains('monitored')
                      ? MonitoredFilter.monitored
                      : s('monitored').contains('unmonitored')
                      ? MonitoredFilter.unmonitored
                      : MonitoredFilter.any,
                  file: s('file').contains('downloaded')
                      ? FileFilter.downloaded
                      : s('file').contains('missing')
                      ? FileFilter.missing
                      : FileFilter.any,
                  availability: {
                    for (final m in MinimumAvailability.values)
                      if (s('availability').contains(m.name)) m,
                  },
                  qualityProfiles: {
                    for (final v in s('profile')) ?int.tryParse(v),
                  },
                  tags: {for (final v in s('tag')) ?int.tryParse(v)},
                  collections: {...s('collection')},
                ),
                saveAsDefault: save,
              );
        },
      ),
    );
  }
}
