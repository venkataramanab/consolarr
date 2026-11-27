// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/lookup_search.dart';
import 'package:consolarr/features/sonarr/presentation/add/add_options_sheet.dart';
import 'package:consolarr/features/sonarr/presentation/formatters.dart';
import 'package:consolarr/features/sonarr/presentation/screen_tracking.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:consolarr/shared/errors/connection_error_message.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Longest wait after the last keystroke before the lookup starts.
const _debounce = Duration(milliseconds: 400);

/// Add series (SON-19): search by title or external id, results with an
/// "already in library" marker, and the options sheet to add one.
///
/// Lookup artwork points at third-party hosts, so results always show a
/// placeholder: the app only talks to the user's own server.
class AddSeriesScreen extends ConsumerStatefulWidget {
  const AddSeriesScreen({this.initialTerm, super.key});

  /// Pre-filled search term (from the library "search to add" shortcut).
  final String? initialTerm;

  @override
  ConsumerState<AddSeriesScreen> createState() => _AddSeriesScreenState();
}

class _AddSeriesScreenState extends ConsumerState<AddSeriesScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTerm,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if ((widget.initialTerm ?? '').isNotEmpty) {
      // Not before the first frame: the provider reads the session.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(_controller.text);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String text) {
    _timer?.cancel();
    unawaited(ref.read(lookupSearchProvider.notifier).search(text));
  }

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _search(text));
    setState(() {});
  }

  void _clear() {
    _controller.clear();
    _search('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(lookupSearchProvider);
    return TrackScreen(
      screen: ScreenName.sonarrAddSeries,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.sonarrAddTitle)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ConsolarrSpacing.gutter,
                ConsolarrSpacing.sm,
                ConsolarrSpacing.gutter,
                ConsolarrSpacing.sm,
              ),
              child: TextField(
                controller: _controller,
                autofocus: widget.initialTerm == null,
                textInputAction: TextInputAction.search,
                maxLength: lookupMaxTermLength,
                buildCounter: (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
                decoration: InputDecoration(
                  labelText: l10n.sonarrAddSearchLabel,
                  hintText: l10n.sonarrAddSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.sonarrAddClearSearch,
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        ),
                ),
                onChanged: _onChanged,
                onSubmitted: _search,
              ),
            ),
            Expanded(
              child: _Results(
                state: state,
                onRetry: () => _search(_controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state, required this.onRetry});

  final LookupState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (state) {
      LookupIdle() => EmptyState(
        icon: Icons.travel_explore,
        headline: l10n.sonarrAddIdleHeadline,
        message: l10n.sonarrAddIdleMessage,
      ),
      LookupSearching() => Semantics(
        label: l10n.sonarrAddSearching,
        liveRegion: true,
        child: ExcludeSemantics(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
            itemCount: 6,
            itemBuilder: (context, index) => const Padding(
              padding: EdgeInsets.only(bottom: ConsolarrSpacing.sm),
              child: SkeletonBox(height: 88, borderRadius: ConsolarrRadii.card),
            ),
          ),
        ),
      ),
      LookupFailed(:final error) => _failed(l10n, error),
      LookupResults(:final results) =>
        results.isEmpty
            ? EmptyState(
                icon: Icons.search_off,
                headline: l10n.sonarrAddNoResultsHeadline,
                message: l10n.sonarrAddNoResultsMessage,
              )
            : _list(context, results),
    };
  }

  Widget _failed(AppLocalizations l10n, AppError error) {
    final message = connectionErrorMessage(l10n, error);
    return ErrorState(
      headline: l10n.sonarrAddErrorHeadline,
      message: message.message,
      hint: message.hint,
      retryLabel: l10n.sonarrAddRetry,
      onRetry: onRetry,
    );
  }

  Widget _list(BuildContext context, List<SonarrLookupResult> results) {
    final l10n = context.l10n;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        ConsolarrSpacing.gutter,
        0,
        ConsolarrSpacing.gutter,
        ConsolarrSpacing.xl,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final r = results[index];
        final s = r.series;
        final status = statusText(l10n, s.status);
        final details = [if (s.year != null) '${s.year}', ?s.network, ?status];
        return Padding(
          padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
          child: MediaListTile(
            key: ValueKey('${r.tvdbId}-${s.id}-$index'),
            title: s.title,
            metadata: details,
            semanticsLabel: l10n.sonarrAddResultSemantics(
              s.title,
              [...details, if (r.inLibrary) l10n.sonarrAddInLibrary].join(', '),
            ),
            leading: const ArtworkPlaceholder(),
            trailing: r.inLibrary
                ? StatusChip(
                    label: l10n.sonarrAddInLibrary,
                    icon: Icons.check_circle_outline,
                    tone: StatusTone.success,
                  )
                : const Icon(Icons.add_circle_outline),
            onTap: () {
              final id = r.libraryId;
              if (id != null) {
                unawaited(
                  GoRouter.maybeOf(context)
                      ?.push<void>(sonarrSeriesLocation(id)),
                );
              } else {
                unawaited(showAddOptionsSheet(context: context, lookup: r));
              }
            },
          ),
        );
      },
    );
  }
}
