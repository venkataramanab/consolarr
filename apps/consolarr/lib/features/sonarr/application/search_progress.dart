// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/settings/application/lock_controller.dart';
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

/// How the loop waits while the app is in the background: the step, and the
/// most steps before the search is reported as timed out. Override in tests.
final searchBackgroundPauseProvider = Provider<({Duration step, int maxSteps})>(
  (ref) => (step: const Duration(milliseconds: 500), maxSteps: 240),
);

/// The progress of one search target. Auto-disposed: leaving the screen ends
/// the polling (a disposed notifier stops after the current wait), and the
/// loop also pauses while the app is in the background. A server switch
/// rebuilds it: a search started on one server never reports its result for
/// the same-numbered item of another.
final searchProgressProvider = NotifierProvider.autoDispose
    .family<SearchProgressNotifier, SearchProgress, SearchTarget>(
      SearchProgressNotifier.new,
    );

class SearchProgressNotifier extends Notifier<SearchProgress> {
  SearchProgressNotifier(this.target);

  final SearchTarget target;

  /// Bumped by every build (server switch). Work for an earlier build drops
  /// its result after each await.
  int _generation = 0;

  @override
  SearchProgress build() {
    _generation++;
    ref.watch(sonarrSessionProvider.select((s) => s.value?.serverId));
    return const SearchIdle();
  }

  /// Starts the search once; ignored while one is already running.
  Future<void> start() async {
    if (state is SearchRunning) return;
    final session = ref.read(sonarrSessionProvider).value;
    if (session == null) return;
    final generation = _generation;
    bool stale() => !ref.mounted || generation != _generation;
    state = const SearchRunning();
    final tracker = ref.read(eventTrackerProvider)
      ..track(SearchStartedEvent(scope: target.scope));

    SearchProgress failed(AppError error) {
      tracker.track(
        SearchFinishedEvent(
          scope: target.scope,
          outcome: SonarrSearchOutcomeParam.failed,
        ),
      );
      return SearchFailed(error);
    }

    // What is in the queue before the search: only items that appear after
    // it count as found. A failed read does not fail the search: the baseline
    // is then unknown (null) and the outcome can never be reported as found.
    final before = await session.api.queue();
    if (stale()) return;
    final knownIds = before.valueOrNull?.map((i) => i.id).toSet();
    final started = await session.api.startCommand(target.request);
    if (stale()) return;
    final command = started.valueOrNull;
    if (command == null) {
      state = failed(started.errorOrNull!);
      return;
    }
    final result = await _poll(session.api, command.id, knownIds, stale);
    if (stale()) return;
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

  Future<SearchProgress> _poll(
    SonarrApi api,
    int commandId,
    Set<int>? knownIds,
    bool Function() stale,
  ) async {
    final delays = ref.read(searchPollDelaysProvider);
    final pause = ref.read(searchBackgroundPauseProvider);
    var errors = 0;
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      // Stop when the screen is gone; pause while the app is in background
      // or locked (the content stays mounted behind the lock), but not
      // forever.
      var waited = 0;
      while (!stale() && (!_isForeground() || ref.read(appLockedProvider))) {
        if (++waited > pause.maxSteps) return const SearchTimedOut();
        await Future<void>.delayed(pause.step);
      }
      if (stale()) return const SearchIdle();
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
      return _outcome(api, knownIds);
    }
    return const SearchTimedOut();
  }

  bool _isForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// A finished command does not say what it found: an item that was not in
  /// the queue before the search ([knownIds]) and belongs to the target means
  /// a release was grabbed. Items that were already queued never count.
  ///
  /// Without a baseline ([knownIds] is null: the queue could not be read
  /// before the search) nothing can be told apart from what was already
  /// queued, so the result is [SearchTimedOut] ("still searching, check the
  /// queue"), never a guessed [SearchGrabbed] or [SearchNothingFound].
  Future<SearchProgress> _outcome(SonarrApi api, Set<int>? knownIds) async {
    if (knownIds == null) return const SearchTimedOut();
    final queue = await api.queue();
    final items = queue.valueOrNull;
    if (items == null) {
      return const SearchFailed(AppError(ErrorCategory.parseError));
    }
    final grabbed = items.any(
      (i) =>
          !knownIds.contains(i.id) &&
          switch (target.scope) {
            SonarrSearchScopeParam.episode => i.episodeId == target.episodeId,
            SonarrSearchScopeParam.season =>
              i.seriesId == target.seriesId &&
                  i.seasonNumber == target.seasonNumber,
            SonarrSearchScopeParam.series => i.seriesId == target.seriesId,
            // Across the library: anything new is a result of this search.
            SonarrSearchScopeParam.missing => true,
          },
    );
    return grabbed ? const SearchGrabbed() : const SearchNothingFound();
  }
}
