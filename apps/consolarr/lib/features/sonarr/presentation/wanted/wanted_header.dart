// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/application/search_progress.dart';
import 'package:consolarr/features/sonarr/application/wanted_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Scope selector as choice chips (one tap, no gesture needed).
class WantedScopeSelector extends ConsumerWidget {
  const WantedScopeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scope = ref.watch(wantedScopeProvider);
    final labels = {
      WantedScope.wanted: l10n.sonarrWantedScopeWanted,
      WantedScope.missing: l10n.sonarrWantedScopeMissing,
      WantedScope.upcoming: l10n.sonarrWantedScopeUpcoming,
    };
    return Semantics(
      container: true,
      label: l10n.sonarrWantedScopeLabel,
      child: Wrap(
        spacing: 8,
        children: [
          for (final e in labels.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: scope == e.key,
              onSelected: (_) =>
                  ref.read(wantedScopeProvider.notifier).select(e.key),
            ),
        ],
      ),
    );
  }
}

/// Scope selector, series filter and the search-all-missing control.
class WantedHeader extends ConsumerStatefulWidget {
  const WantedHeader({
    required this.showSearchAll,
    required this.searchAllEnabled,
    super.key,
  });

  final bool showSearchAll;
  final bool searchAllEnabled;

  @override
  ConsumerState<WantedHeader> createState() => _WantedHeaderState();
}

class _WantedHeaderState extends ConsumerState<WantedHeader> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(wantedFilterProvider),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmSearchAll() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Title, body and buttons scroll together: at the largest text size
        // the body must stay readable on a small screen.
        scrollable: true,
        title: Text(l10n.sonarrWantedSearchAllTitle),
        content: Text(l10n.sonarrWantedSearchAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.sonarrWantedCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.sonarrWantedSearchAllConfirm),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref
          .read(searchProgressProvider(const SearchTarget.missing()).notifier)
          .start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = ref.watch(wantedFilterProvider);
    // Keep the field in sync when the filter is cleared from elsewhere.
    if (filter.isEmpty && _controller.text.isNotEmpty) _controller.clear();
    final progress = ref.watch(
      searchProgressProvider(const SearchTarget.missing()),
    );
    final running = progress is SearchRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WantedScopeSelector(),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.sonarrWantedFilterHint,
            prefixIcon: const Icon(Icons.filter_list),
            suffixIcon: filter.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.sonarrWantedFilterClear,
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        ref.read(wantedFilterProvider.notifier).set(''),
                  ),
          ),
          onChanged: ref.read(wantedFilterProvider.notifier).set,
        ),
        if (widget.showSearchAll) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: widget.searchAllEnabled && !running
                  ? _confirmSearchAll
                  : null,
              icon: const Icon(Icons.search),
              label: Text(l10n.sonarrWantedSearchAll),
            ),
          ),
          _SearchAllStatus(progress: progress, onRetry: _confirmSearchAll),
        ],
      ],
    );
  }
}

class _SearchAllStatus extends StatelessWidget {
  const _SearchAllStatus({required this.progress, required this.onRetry});

  final SearchProgress progress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = switch (progress) {
      SearchIdle() => null,
      SearchRunning() => l10n.sonarrWantedSearchAllRunning,
      SearchFailed() => l10n.sonarrWantedSearchAllFailed,
      SearchGrabbed() => l10n.sonarrWantedSearchAllDone,
      SearchNothingFound() => l10n.sonarrWantedSearchAllNothing,
      SearchTimedOut() => l10n.sonarrWantedSearchAllTimedOut,
    };
    if (text == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            if (progress is SearchFailed)
              TextButton(
                onPressed: onRetry,
                child: Text(l10n.sonarrWantedSearchAllRetry),
              ),
          ],
        ),
      ),
    );
  }
}
