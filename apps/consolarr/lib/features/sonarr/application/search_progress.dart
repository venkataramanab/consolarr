// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// What an automatic search is for (SON-16, SON-17, SON-20).
@immutable
class SearchTarget {
  const SearchTarget.episode(int this.episodeId)
    : scope = SonarrSearchScopeParam.episode,
      seriesId = null,
      seasonNumber = null;

  const SearchTarget.season({
    required int this.seriesId,
    required int this.seasonNumber,
  }) : scope = SonarrSearchScopeParam.season,
       episodeId = null;

  const SearchTarget.series(int this.seriesId)
    : scope = SonarrSearchScopeParam.series,
      episodeId = null,
      seasonNumber = null;

  /// "Search all missing" across the library.
  const SearchTarget.missing()
    : scope = SonarrSearchScopeParam.missing,
      episodeId = null,
      seriesId = null,
      seasonNumber = null;

  final SonarrSearchScopeParam scope;
  final int? episodeId;
  final int? seriesId;
  final int? seasonNumber;

  ArrCommandRequest get request => switch (scope) {
    SonarrSearchScopeParam.episode => ArrCommandRequest('EpisodeSearch', {
      'episodeIds': [episodeId],
    }),
    SonarrSearchScopeParam.season => ArrCommandRequest('SeasonSearch', {
      'seriesId': seriesId,
      'seasonNumber': seasonNumber,
    }),
    SonarrSearchScopeParam.series => ArrCommandRequest('SeriesSearch', {
      'seriesId': seriesId,
    }),
    SonarrSearchScopeParam.missing => const ArrCommandRequest(
      'MissingEpisodeSearch',
      {'monitored': true},
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is SearchTarget &&
      other.scope == scope &&
      other.episodeId == episodeId &&
      other.seriesId == seriesId &&
      other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(scope, episodeId, seriesId, seasonNumber);
}

/// Progress of one automatic search, as shown inline on its row.
sealed class SearchProgress {
  const SearchProgress();
}

/// Nothing started (or the user dismissed the result).
final class SearchIdle extends SearchProgress {
  const SearchIdle();
}

/// The command was sent and is queued or running.
final class SearchRunning extends SearchProgress {
  const SearchRunning();
}

/// The search finished and something is now in the download queue.
final class SearchGrabbed extends SearchProgress {
  const SearchGrabbed();
}

/// The search finished without a release to grab.
final class SearchNothingFound extends SearchProgress {
  const SearchNothingFound();
}

/// Starting or polling failed; retry is offered.
final class SearchFailed extends SearchProgress {
  const SearchFailed(this.error);
  final AppError error;
}

/// The command did not finish within the polling cap.
final class SearchTimedOut extends SearchProgress {
  const SearchTimedOut();
}

/// Waits between status polls: grows, then holds, and bounds the total. The
/// loop ends after the list is used up, so a slow server never causes endless
/// polling. Override in tests with zero delays.
final searchPollDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 1),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
  ],
);

/// Polling failures in a row before the search is reported as failed.
const _maxConsecutivePollErrors = 3;

/// The progress of one search target. Auto-disposed: leaving the screen ends
/// the polling (a disposed notifier stops after the current wait), and the
/// loop also pauses while the app is in the background.
final searchProgressProvider = NotifierProvider.autoDispose
    .family<SearchProgressNotifier, SearchProgress, SearchTarget>(
      SearchProgressNotifier.new,
    );

class SearchProgressNotifier extends Notifier<SearchProgress> {
  SearchProgressNotifier(this.target);

  final SearchTarget target;

  @override
  SearchProgress build() => const SearchIdle();

  /// Starts the search once; ignored while one is already running.
  Future<void> start() async {
    if (state is SearchRunning) return;
    final session = ref.read(sonarrSessionProvider).value;
    if (session == null) return;
    state = const SearchRunning();
    final tracker = ref.read(eventTrackerProvider)
      ..track(SearchStartedEvent(scope: target.scope));
    final started = await session.api.startCommand(target.request);
    if (!ref.mounted) return;
    final command = started.valueOrNull;
    if (command == null) {
      state = SearchFailed(started.errorOrNull!);
      tracker.track(
        SearchFinishedEvent(
          scope: target.scope,
          outcome: SonarrSearchOutcomeParam.failed,
        ),
      );
      return;
    }
    final result = await _poll(session.api, command.id);
    if (!ref.mounted) return;
    state = result;
    tracker.track(
      SearchFinishedEvent(
        scope: target.scope,
        outcome: switch (result) {
          SearchGrabbed() => SonarrSearchOutcomeParam.grabbed,
          SearchNothingFound() => SonarrSearchOutcomeParam.nothingFound,
          SearchTimedOut() => SonarrSearchOutcomeParam.timedOut,
          _ => SonarrSearchOutcomeParam.failed,
        },
      ),
    );
  }

  /// Back to idle (dismiss a result).
  void reset() {
    if (state is! SearchRunning) state = const SearchIdle();
  }

  Future<SearchProgress> _poll(SonarrApi api, int commandId) async {
    final delays = ref.read(searchPollDelaysProvider);
    var errors = 0;
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      // Stop when the screen is gone; pause while the app is in background.
      while (ref.mounted && !_isForeground()) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!ref.mounted) return const SearchIdle();
      final result = await api.command(commandId);
      final command = result.valueOrNull;
      if (command == null) {
        final error = result.errorOrNull!;
        errors++;
        if (error.category == ErrorCategory.authFailed ||
            errors >= _maxConsecutivePollErrors) {
          return SearchFailed(error);
        }
        continue;
      }
      errors = 0;
      if (!command.isTerminal) continue;
      if (!command.isSuccess) {
        return const SearchFailed(AppError(ErrorCategory.serverError));
      }
      return _outcome(api);
    }
    return const SearchTimedOut();
  }

  bool _isForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// A finished command does not say what it found: something in the queue
  /// for the target means a release was grabbed.
  Future<SearchProgress> _outcome(SonarrApi api) async {
    final queue = await api.queue();
    final items = queue.valueOrNull;
    if (items == null)
      return const SearchFailed(AppError(ErrorCategory.parseError));
    final grabbed = items.any(
      (i) => switch (target.scope) {
        SonarrSearchScopeParam.episode => i.episodeId == target.episodeId,
        SonarrSearchScopeParam.season =>
          i.seriesId == target.seriesId &&
              i.seasonNumber == target.seasonNumber,
        SonarrSearchScopeParam.series => i.seriesId == target.seriesId,
        SonarrSearchScopeParam.missing => false,
      },
    );
    return grabbed ? const SearchGrabbed() : const SearchNothingFound();
  }
}
