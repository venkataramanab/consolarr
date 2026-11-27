// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Progress of an automatic search, as a plain view-model value.
enum ArrSearchStatus {
  idle,
  searching,
  grabbed,
  nothingFound,
  failed,

  /// The command finished without telling what it found ("Search finished").
  finished,

  /// Still running on the server after the polling cap: neutral, no retry.
  stillRunning,
}

/// Localized strings of [ArrSearchButton] (passed in; no l10n here).
class ArrSearchLabels {
  const ArrSearchLabels({
    required this.search,
    required this.searching,
    required this.grabbed,
    required this.nothingFound,
    required this.failed,
    required this.retry,
    this.finished,
    this.stillRunning,
  });

  /// Tooltip / name of the idle button, for example "Search for this episode".
  final String search;
  final String searching;
  final String grabbed;
  final String nothingFound;
  final String failed;
  final String retry;

  /// Text of [ArrSearchStatus.finished]; falls back to [grabbed].
  final String? finished;

  /// Text of [ArrSearchStatus.stillRunning]; falls back to [searching].
  final String? stillRunning;
}

/// Inline control for an automatic search (SON-16): an icon button while idle,
/// then the state as icon and text (never colour alone); "nothing found" and
/// "failed" offer a retry. Kind-agnostic: used by Sonarr rows now and Radarr
/// later. The searching state is announced as a live region and does not
/// animate under reduced motion.
class ArrSearchButton extends StatelessWidget {
  const ArrSearchButton({
    required this.status,
    required this.labels,
    required this.onSearch,
    this.enabled = true,
    super.key,
  });

  final ArrSearchStatus status;
  final ArrSearchLabels labels;

  /// Starts the search (also the retry action).
  final VoidCallback onSearch;

  /// Whether starting a search is possible (false: offline, for example). The
  /// idle button is then shown disabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ArrSearchStatus.idle:
        return IconButton(
          tooltip: labels.search,
          icon: const Icon(Icons.search),
          onPressed: enabled ? onSearch : null,
        );
      case ArrSearchStatus.searching:
        final reduce = !ConsolarrEffects.of(context).animate;
        return Semantics(
          liveRegion: true,
          label: labels.searching,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.sm,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ConsolarrSpacing.minTapTarget,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: reduce ? 0.6 : null,
                      ),
                    ),
                    const SizedBox(width: ConsolarrSpacing.sm),
                    Flexible(child: Text(labels.searching)),
                  ],
                ),
              ),
            ),
          ),
        );
      case ArrSearchStatus.grabbed:
        return Semantics(
          liveRegion: true,
          child: StatusChip(
            label: labels.grabbed,
            icon: Icons.download_done,
            tone: StatusTone.success,
          ),
        );
      case ArrSearchStatus.finished:
        return Semantics(
          liveRegion: true,
          child: StatusChip(
            label: labels.finished ?? labels.grabbed,
            icon: Icons.check_circle_outline,
            tone: StatusTone.success,
          ),
        );
      case ArrSearchStatus.stillRunning:
        return Semantics(
          liveRegion: true,
          child: StatusChip(
            label: labels.stillRunning ?? labels.searching,
            icon: Icons.schedule,
            tone: StatusTone.info,
          ),
        );
      case ArrSearchStatus.nothingFound:
      case ArrSearchStatus.failed:
        final nothing = status == ArrSearchStatus.nothingFound;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Semantics(
                liveRegion: true,
                child: StatusChip(
                  label: nothing ? labels.nothingFound : labels.failed,
                  icon: nothing ? Icons.search_off : Icons.error_outline,
                  tone: nothing ? StatusTone.neutral : StatusTone.warning,
                ),
              ),
            ),
            IconButton(
              tooltip: labels.retry,
              icon: const Icon(Icons.refresh),
              onPressed: onSearch,
            ),
          ],
        );
    }
  }
}
