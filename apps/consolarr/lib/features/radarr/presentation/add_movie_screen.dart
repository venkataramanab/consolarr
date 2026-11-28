// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/add_options_form.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/common.dart';
import 'package:consolarr/features/radarr/presentation/movie_views.dart';
import 'package:consolarr/features/radarr/presentation/navigation.dart';
import 'package:consolarr/features/radarr/presentation/options_state.dart';
import 'package:consolarr/features/radarr/presentation/screen_view.dart';
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
                          if (m.year case final year?) l10n.plainInt(year),
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
    // Everything the callback needs is taken now: it runs after the sheet is
    // gone, and this screen may be gone by then too.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final success = l10n.radarrAddSuccess;
    final lookup = ref.read(movieLookupProvider.notifier);
    final term = _controller.text;
    return showGlassSheet<void>(
      context: context,
      title: l10n.radarrAddOptionsTitle,
      closeLabel: l10n.radarrClose,
      detents: GlassSheetDetents.full,
      // The sheet paints its own surface: tiles need a Material of their own.
      scrollBuilder: (context, controller) => Material(
        type: MaterialType.transparency,
        child: AddOptionsForm(
          movie: movie,
          controller: controller,
          onAdded: () {
            messenger?.showSnackBar(SnackBar(content: Text(success)));
            // Re-run the lookup so the row shows the "in library" marker.
            if (mounted) lookup.search(term);
          },
        ),
      ),
    );
  }
}

/// Options for one movie (profile, availability, folder, monitored, tags,
/// search after add and, when the lookup has one, the collection switch).
class AddOptionsForm extends ConsumerStatefulWidget {
  const AddOptionsForm({
    required this.movie,
    required this.onAdded,
    this.controller,
    super.key,
  });

  final RadarrMovie movie;
  final VoidCallback onAdded;
  final ScrollController? controller;

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
    // A second tap while the request is in flight sends nothing.
    if (_adding || profile == null || root == null) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    // Provider-owned function: it stays valid after this sheet is popped.
    final add = ref.read(addMovieActionProvider);
    final navigator = Navigator.of(context);
    final onAdded = widget.onAdded;
    final error = await add(
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
    if (error == null) {
      // Added: close the sheet (if the user did not already) and tell the
      // screen, which guards its own use of `ref` and `context`.
      if (mounted) navigator.pop();
      onAdded();
      return;
    }
    if (!mounted) return;
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
    final tagsAsync = ref.watch(tagsProvider);
    final rememberedAsync = ref.watch(defaultRootFolderProvider);
    // The remembered folder is part of the load: the default is picked once.
    final (load, loadError) = optionsLoad([
      profiles,
      roots,
      tagsAsync,
      rememberedAsync,
    ]);
    final padding = const EdgeInsets.fromLTRB(
      ConsolarrSpacing.gutter,
      0,
      ConsolarrSpacing.gutter,
      ConsolarrSpacing.lg,
    );
    if (load == OptionsLoad.loading) return const OptionsLoading();
    if (load == OptionsLoad.failed) {
      return OptionsError(error: loadError!, onRetry: () => retryOptions(ref));
    }
    final tags = tagsAsync.value ?? const <ArrTag>[];
    final remembered = rememberedAsync.value;
    final profileList = profiles.value ?? const <ArrQualityProfile>[];
    final rootList = roots.value ?? const <ArrRootFolder>[];
    _profile ??= profileList.isEmpty ? null : profileList.first.id;
    _root ??= rootList.isEmpty
        ? null
        : (rootList.any((r) => r.path == remembered)
              ? remembered
              : rootList.first.path);
    final ready = _profile != null && _root != null;
    final hasCollection = widget.movie.collectionTitle != null;
    return ListView(
      controller: widget.controller,
      padding: padding,
      children: [
        Text(
          widget.movie.year == null
              ? widget.movie.title
              : l10n.sharedTitleWithYear(
                  widget.movie.title,
                  l10n.plainInt(widget.movie.year!),
                ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        if (!ready)
          Text(l10n.radarrAddNeedsSetup)
        else ...[
          ArrOptionPicker<int>(
            label: l10n.radarrQualityProfile,
            value: _profile,
            options: [for (final p in profileList) ArrOption(p.id, p.name)],
            onChanged: (v) {
              if (!_adding) setState(() => _profile = v);
            },
          ),
          ArrOptionPicker<String>(
            label: l10n.radarrRootFolder,
            value: _root,
            options: [for (final r in rootList) ArrOption(r.path, r.path)],
            onChanged: (v) {
              if (!_adding) setState(() => _root = v);
            },
          ),
          ArrOptionPicker<MinimumAvailability>(
            label: l10n.radarrMinimumAvailability,
            value: _min,
            options: [
              for (final m in MinimumAvailability.values)
                if (m != MinimumAvailability.unknown)
                  ArrOption(m, minimumAvailabilityText(l10n, m)),
            ],
            onChanged: (v) {
              if (!_adding) setState(() => _min = v);
            },
          ),
          ArrOptionSwitch(
            title: l10n.radarrMonitored,
            value: _monitored,
            onChanged: (v) {
              if (!_adding) setState(() => _monitored = v);
            },
          ),
          ArrOptionSwitch(
            title: l10n.radarrSearchAfterAdd,
            value: _search,
            onChanged: (v) {
              if (!_adding) setState(() => _search = v);
            },
          ),
          if (hasCollection)
            ArrOptionSwitch(
              title: l10n.radarrAddCollection,
              subtitle: l10n.radarrAddCollectionHint(
                widget.movie.collectionTitle!,
              ),
              value: _collection,
              onChanged: (v) {
                if (!_adding) setState(() => _collection = v);
              },
            ),
          if (tags.isNotEmpty) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                header: true,
                child: Text(
                  l10n.radarrTags,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: context.roles.textPrimary),
                ),
              ),
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
                '${connectionErrorMessage(l10n, _error!, kind: ServiceKind.radarr).message}',
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
