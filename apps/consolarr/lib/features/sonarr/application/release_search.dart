// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// What an interactive release search looks for (SON-18).
@immutable
class InteractiveSearchTarget {
  const InteractiveSearchTarget.episode(int this.episodeId)
    : seriesId = null,
      seasonNumber = null;

  const InteractiveSearchTarget.season({
    required int this.seriesId,
    required int this.seasonNumber,
  }) : episodeId = null;

  final int? episodeId;
  final int? seriesId;
  final int? seasonNumber;

  @override
  bool operator ==(Object other) =>
      other is InteractiveSearchTarget &&
      other.episodeId == episodeId &&
      other.seriesId == seriesId &&
      other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(episodeId, seriesId, seasonNumber);
}

/// Sort keys of the release list.
enum ReleaseSort { bestMatch, age, size, seeders, indexer, quality }

/// Accepted/rejected filter.
enum ReleaseDecision { all, accepted, rejected }

/// Sort and filter choices of the release sheet. Local only.
@immutable
class ReleaseView {
  const ReleaseView({
    this.sort = ReleaseSort.bestMatch,
    this.reversed = false,
    this.decision = ReleaseDecision.all,
    this.protocol,
    this.resolutions = const {},
    this.sources = const {},
  });

  final ReleaseSort sort;

  /// Opposite of the key's natural direction (best first, newest first,
  /// biggest first, A to Z).
  final bool reversed;
  final ReleaseDecision decision;
  final ArrProtocol? protocol;
  final Set<int> resolutions;
  final Set<String> sources;

  int get activeFilters =>
      (decision == ReleaseDecision.all ? 0 : 1) +
      (protocol == null ? 0 : 1) +
      resolutions.length +
      sources.length;

  bool get isFiltered => activeFilters > 0;

  ReleaseView copyWith({
    ReleaseSort? sort,
    bool? reversed,
    ReleaseDecision? decision,
    ArrProtocol? protocol,
    bool clearProtocol = false,
    Set<int>? resolutions,
    Set<String>? sources,
  }) => ReleaseView(
    sort: sort ?? this.sort,
    reversed: reversed ?? this.reversed,
    decision: decision ?? this.decision,
    protocol: clearProtocol ? null : (protocol ?? this.protocol),
    resolutions: resolutions ?? this.resolutions,
    sources: sources ?? this.sources,
  );

  /// Same sort, no filters.
  ReleaseView cleared() => ReleaseView(sort: sort, reversed: reversed);
}

int _cmp(ArrRelease a, ArrRelease b, ReleaseSort sort) => switch (sort) {
  ReleaseSort.bestMatch => a.releaseWeight.compareTo(b.releaseWeight),
  ReleaseSort.age => a.ageMinutes.compareTo(b.ageMinutes),
  ReleaseSort.size => b.size.compareTo(a.size),
  ReleaseSort.seeders => (b.seeders ?? -1).compareTo(a.seeders ?? -1),
  ReleaseSort.indexer => (a.indexer ?? '').toLowerCase().compareTo(
    (b.indexer ?? '').toLowerCase(),
  ),
  ReleaseSort.quality => (b.resolution ?? 0).compareTo(a.resolution ?? 0),
};

/// Filters and sorts [all] by [view]. Stable: ties keep the server order.
List<ArrRelease> applyReleaseView(List<ArrRelease> all, ReleaseView view) {
  final kept = [
    for (final r in all)
      if (_matches(r, view)) r,
  ];
  final indexed = [for (var i = 0; i < kept.length; i++) (i, kept[i])];
  indexed.sort((x, y) {
    var c = _cmp(x.$2, y.$2, view.sort);
    if (view.reversed) c = -c;
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}

bool _matches(ArrRelease r, ReleaseView v) {
  switch (v.decision) {
    case ReleaseDecision.all:
      break;
    case ReleaseDecision.accepted:
      if (r.isRejected) return false;
    case ReleaseDecision.rejected:
      if (!r.isRejected) return false;
  }
  if (v.protocol != null && r.protocol != v.protocol) return false;
  if (v.resolutions.isNotEmpty && !v.resolutions.contains(r.resolution)) {
    return false;
  }
  if (v.sources.isNotEmpty && !v.sources.contains(r.source)) return false;
  return true;
}

/// The releases of one search. Loading is the provider's `AsyncLoading`,
/// failure its `AsyncError` (carrying an [AppError]).
final releaseSearchProvider = AsyncNotifierProvider.autoDispose
    .family<ReleaseSearchNotifier, List<ArrRelease>, InteractiveSearchTarget>(
      ReleaseSearchNotifier.new,
      retry: (_, _) => null,
    );

class ReleaseSearchNotifier extends AsyncNotifier<List<ArrRelease>> {
  ReleaseSearchNotifier(this.target);

  final InteractiveSearchTarget target;

  @override
  Future<List<ArrRelease>> build() async {
    final session = await ref.watch(sonarrSessionProvider.future);
    if (session == null) throw const AppError(ErrorCategory.notFound);
    final result = await session.api.releases(
      episodeId: target.episodeId,
      seriesId: target.seriesId,
      seasonNumber: target.seasonNumber,
    );
    return result.when(ok: (v) => v, err: (e) => throw e);
  }

  /// Searches again.
  void retry() => ref.invalidateSelf();
}

/// Sort and filter of one sheet.
final releaseViewProvider = NotifierProvider.autoDispose
    .family<ReleaseViewNotifier, ReleaseView, InteractiveSearchTarget>(
      ReleaseViewNotifier.new,
    );

class ReleaseViewNotifier extends Notifier<ReleaseView> {
  ReleaseViewNotifier(this.target);

  final InteractiveSearchTarget target;

  @override
  ReleaseView build() => const ReleaseView();

  // The setter-style API reads better at call sites than a `state` write.
  void update(ReleaseView Function(ReleaseView current) change) =>
      state = change(state);

  void clearFilters() => state = state.cleared();
}

/// Per-release download state.
enum GrabStatus {
  grabbing,
  grabbed,

  /// The server answered with a failure; nothing was sent.
  failed,

  /// The request may have reached the server (timeout, dropped connection).
  /// Retrying needs an explicit tap and the queue should be checked first.
  maybeSent,
}

/// Key of a release in [releaseGrabProvider].
String grabKey(ArrRelease r) => '${r.indexerId}/${r.guid}';

/// Download states of one sheet, by [grabKey].
final releaseGrabProvider = NotifierProvider.autoDispose
    .family<
      ReleaseGrabNotifier,
      Map<String, GrabStatus>,
      InteractiveSearchTarget
    >(ReleaseGrabNotifier.new);

class ReleaseGrabNotifier extends Notifier<Map<String, GrabStatus>> {
  ReleaseGrabNotifier(this.target);

  final InteractiveSearchTarget target;

  /// Bumped by every build, which a server switch triggers. Work started for
  /// an earlier build drops its result: a grab started on server A never
  /// shows up against the same-numbered release of server B.
  int _generation = 0;

  @override
  Map<String, GrabStatus> build() {
    _generation++;
    ref.watch(sonarrSessionProvider.select((s) => s.value?.serverId));
    return const {};
  }

  /// Sends [release] to the download client once. Ignored while it is being
  /// grabbed or after it was grabbed: no automatic retry exists, so a dropped
  /// connection can never submit twice without a new explicit tap.
  /// [confirmedRejected] records that the user accepted a rejected release.
  ///
  /// A release in the [GrabStatus.maybeSent] state is only sent again with
  /// [confirmedResend], which the caller sets after [confirmQueued] found
  /// nothing and the user said "send again".
  Future<void> grab(
    ArrRelease release, {
    bool confirmedRejected = false,
    bool confirmedResend = false,
  }) async {
    final key = grabKey(release);
    final current = state[key];
    if (current == GrabStatus.grabbing || current == GrabStatus.grabbed) {
      return;
    }
    if (current == GrabStatus.maybeSent && !confirmedResend) return;
    final session = ref.read(sonarrSessionProvider).value;
    if (session == null) return;
    final generation = _generation;
    final tracker = ref.read(eventTrackerProvider);
    if (confirmedRejected) {
      tracker.track(
        const SonarrReleaseGrabbedEvent(
          outcome: SonarrGrabOutcomeParam.rejectedConfirmed,
        ),
      );
    }
    state = {...state, key: GrabStatus.grabbing};
    final result = await session.api.grabRelease(release);
    final error = result.errorOrNull;
    tracker.track(
      SonarrReleaseGrabbedEvent(
        outcome: error == null
            ? SonarrGrabOutcomeParam.grabbed
            : SonarrGrabOutcomeParam.failed,
      ),
    );
    if (!ref.mounted || generation != _generation) return;
    state = {
      ...state,
      key: error == null
          ? GrabStatus.grabbed
          : switch (error.category) {
              ErrorCategory.timeout ||
              ErrorCategory.networkUnreachable ||
              ErrorCategory.parseError => GrabStatus.maybeSent,
              _ => GrabStatus.failed,
            },
    };
  }

  /// Whether queue item [item] is [release]: the download client's id (when
  /// both sides give one, it is usually the torrent hash inside the release
  /// guid) or the same title, compared without case and surrounding space.
  static bool _isRelease(ArrQueueItem item, ArrRelease release) {
    final id = item.downloadId?.trim().toLowerCase();
    if (id != null &&
        id.length >= 16 &&
        release.guid.toLowerCase().contains(id)) {
      return true;
    }
    return item.title.trim().toLowerCase() ==
        release.title.trim().toLowerCase();
  }

  /// For a [GrabStatus.maybeSent] release: looks for it in the download queue.
  /// Found means the first request did arrive; it is then shown as grabbed
  /// and `true` is returned. Not found, or the queue could not be read, is
  /// `false`: the caller must ask before sending again.
  ///
  /// The queue snapshot is bounded: the client reads at most 5 pages of 200,
  /// so 1,000 items. A release beyond that is not found and is treated as
  /// "not queued" (the caller asks before sending again).
  Future<bool> confirmQueued(ArrRelease release) async {
    final key = grabKey(release);
    if (state[key] != GrabStatus.maybeSent) return false;
    final session = ref.read(sonarrSessionProvider).value;
    if (session == null) return false;
    final generation = _generation;
    final result = await session.api.queue();
    if (!ref.mounted || generation != _generation) return false;
    final items = result.valueOrNull;
    if (items == null || !items.any((i) => _isRelease(i, release))) {
      return false;
    }
    state = {...state, key: GrabStatus.grabbed};
    return true;
  }
}
