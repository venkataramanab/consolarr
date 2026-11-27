// SPDX-License-Identifier: GPL-3.0-or-later

// TODO(arr_common): the add-options pieces are local copies; swap them for the
// shared ones from `features/arr_common` once W4a merges.

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
import 'package:consolarr/features/radarr/presentation/stand_ins/glass_sheet.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Add movie (RAD-14): lookup by title or external id, then an options sheet.
class AddMovieScreen extends ConsumerStatefulWidget {
  const AddMovieScreen({this.initialTerm, super.key});

  final String? initialTerm;

  @override
  ConsumerState<AddMovieScreen> createState() => _AddMovieScreenState();
}

class _AddMovieScreenState extends ConsumerState<AddMovieScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTerm,
  );
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final term = widget.initialTerm;
    if (term != null && term.trim().isNotEmpty) {
      Future<void>.microtask(
        () => ref.read(movieLookupProvider.notifier).search(term),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) ref.read(movieLookupProvider.notifier).search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lookup = ref.watch(movieLookupProvider);
    final source = ref.watch(artworkSourceProvider);
    return RadarrScreenView(
      screen: ScreenName.radarrAddMovie,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.radarrAddMovie)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
              child: TextField(
                controller: _controller,
                autofocus: widget.initialTerm == null,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.radarrAddSearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: _changed,
                onSubmitted: (v) =>
                    ref.read(movieLookupProvider.notifier).search(v),
              ),
            ),
            Expanded(
              child: switch (lookup) {
                LookupIdle() => EmptyState(
                  icon: Icons.add_circle_outline,
                  headline: l10n.radarrAddIdleHeadline,
                  message: l10n.radarrAddIdleMessage,
                ),
                LookupSearching() => Semantics(
                  label: l10n.radarrSearching,
                  liveRegion: true,
                  child: ExcludeSemantics(
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
                      itemCount: 5,
                      itemBuilder: (_, _) => const Padding(
                        padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
                        child: SkeletonBox(
                          height: 88,
                          borderRadius: ConsolarrRadii.card,
                        ),
                      ),
                    ),
                  ),
                ),
                LookupFailed(:final error) => radarrErrorView(
                  context,
                  error,
                  onRetry: () => ref
                      .read(movieLookupProvider.notifier)
                      .search(_controller.text),
                ),
                LookupResults(:final movies) when movies.isEmpty => EmptyState(
                  icon: Icons.search_off,
                  headline: l10n.radarrAddNoResultsHeadline,
                  message: l10n.radarrAddNoResultsMessage,
                ),
                LookupResults(:final movies) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    ConsolarrSpacing.gutter,
                    0,
                    ConsolarrSpacing.gutter,
                    ConsolarrSpacing.xl,
                  ),
                  itemCount: movies.length,
                  itemBuilder: (context, i) {
                    final m = movies[i];
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: ConsolarrSpacing.sm,
                      ),
                      child: MediaListTile(
                        key: ValueKey('${m.tmdbId}-$i'),
                        title: m.title,
                        metadata: [
                          if (m.year != null) '${m.year}',
                          if (m.runtime != null) l10n.radarrRuntime(m.runtime!),
                          ?m.studio,
                        ],
                        semanticsLabel: m.inLibrary
                            ? l10n.radarrAddRowInLibrary(m.title)
                            : l10n.radarrAddRowSemantics(m.title),
                        leading: movieArtwork(
                          source,
                          m,
                          (MediaListTile.thumbWidth *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                        ),
                        trailing: m.inLibrary
                            ? StatusChip(
                                label: l10n.radarrInLibrary,
                                icon: Icons.check,
                                tone: StatusTone.success,
                              )
                            : null,
                        onTap: () => m.inLibrary
                            ? openMovie(context, m.id)
                            : _options(context, m),
                      ),
                    );
                  },
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _options(BuildContext context, RadarrMovie movie) {
    final l10n = context.l10n;
    return showGlassSheet<void>(
      context: context,
      title: l10n.radarrAddOptionsTitle,
      closeLabel: l10n.radarrClose,
      builder: (_) => AddOptionsForm(
        movie: movie,
        onAdded: () {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(content: Text(l10n.radarrAddSuccess)),
          );
          // Re-run the lookup so the row shows the "in library" marker.
          ref.read(movieLookupProvider.notifier).search(_controller.text);
        },
      ),
    );
  }
}

/// Options for one movie (profile, availability, folder, monitored, tags,
/// search after add and, when the lookup has one, the collection switch).
class AddOptionsForm extends ConsumerStatefulWidget {
  const AddOptionsForm({required this.movie, required this.onAdded, super.key});

  final RadarrMovie movie;
  final VoidCallback onAdded;

  @override
  ConsumerState<AddOptionsForm> createState() => _AddOptionsFormState();
}

class _AddOptionsFormState extends ConsumerState<AddOptionsForm> {
  int? _profile;
  String? _root;
  MinimumAvailability _min = MinimumAvailability.released;
  bool _monitored = true;
  bool _search = true;
  bool _collection = false;
  final Set<int> _tags = {};
  bool _adding = false;
  AppError? _error;

  Future<void> _add() async {
    final profile = _profile;
    final root = _root;
    if (profile == null || root == null) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    final error = await addMovie(
      ref,
      AddMovieRequest(
        lookup: widget.movie,
        qualityProfileId: profile,
        rootFolderPath: root,
        minimumAvailability: _min,
        monitored: _monitored,
        tags: _tags.toList()..sort(),
        searchForMovie: _search,
        addCollection: _collection,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      widget.onAdded();
      return;
    }
    setState(() {
      _adding = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profiles = ref.watch(qualityProfilesProvider);
    final roots = ref.watch(rootFoldersProvider);
    final tags = ref.watch(tagsProvider).value ?? const [];
    final remembered = ref.watch(defaultRootFolderProvider).value;
    final profileList = profiles.value ?? const <ArrQualityProfile>[];
    final rootList = roots.value ?? const <ArrRootFolder>[];
    _profile ??= profileList.isEmpty ? null : profileList.first.id;
    _root ??= rootList.isEmpty
        ? null
        : (rootList.any((r) => r.path == remembered)
              ? remembered
              : rootList.first.path);
    final loading = profiles.isLoading || roots.isLoading;
    final ready = _profile != null && _root != null;
    final hasCollection = widget.movie.collectionTitle != null;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.lg,
      ),
      children: [
        Text(
          widget.movie.year == null
              ? widget.movie.title
              : '${widget.movie.title} (${widget.movie.year})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        if (!loading && !ready)
          Text(l10n.radarrAddNeedsSetup)
        else ...[
          DropdownButtonFormField<int>(
            initialValue: _profile,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.radarrQualityProfile),
            items: [
              for (final p in profileList)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: _adding ? null : (v) => setState(() => _profile = v),
          ),
          const SizedBox(height: ConsolarrSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _root,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.radarrRootFolder),
            items: [
              for (final r in rootList)
                DropdownMenuItem(value: r.path, child: Text(r.path)),
            ],
            onChanged: _adding ? null : (v) => setState(() => _root = v),
          ),
          const SizedBox(height: ConsolarrSpacing.md),
          DropdownButtonFormField<MinimumAvailability>(
            initialValue: _min,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.radarrMinimumAvailability,
            ),
            items: [
              for (final m in MinimumAvailability.values)
                if (m != MinimumAvailability.unknown)
                  DropdownMenuItem(
                    value: m,
                    child: Text(minimumAvailabilityText(l10n, m)),
                  ),
            ],
            onChanged: _adding ? null : (v) => setState(() => _min = v ?? _min),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.radarrMonitored),
            value: _monitored,
            onChanged: _adding ? null : (v) => setState(() => _monitored = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.radarrSearchAfterAdd),
            value: _search,
            onChanged: _adding ? null : (v) => setState(() => _search = v),
          ),
          if (hasCollection)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.radarrAddCollection),
              subtitle: Text(
                l10n.radarrAddCollectionHint(widget.movie.collectionTitle!),
              ),
              value: _collection,
              onChanged: _adding
                  ? null
                  : (v) => setState(() => _collection = v),
            ),
          if (tags.isNotEmpty) ...[
            Text(
              l10n.radarrTags,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: ConsolarrSpacing.sm,
              children: [
                for (final t in tags)
                  FilterChip(
                    label: Text(t.label),
                    selected: _tags.contains(t.id),
                    onSelected: _adding
                        ? null
                        : (on) => setState(
                            () => on ? _tags.add(t.id) : _tags.remove(t.id),
                          ),
                  ),
              ],
            ),
          ],
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: ConsolarrSpacing.sm),
              child: Text(
                '${l10n.radarrAddFailed} '
                '${connectionErrorMessage(l10n, _error!).message}',
                style: TextStyle(color: context.roles.error),
              ),
            ),
          ),
        const SizedBox(height: ConsolarrSpacing.md),
        FilledButton(
          onPressed: _adding || !ready ? null : _add,
          child: Text(
            _adding
                ? l10n.radarrAdding
                : _search
                ? l10n.radarrAddAndSearch
                : l10n.radarrAddMovie,
          ),
        ),
      ],
    );
  }
}
