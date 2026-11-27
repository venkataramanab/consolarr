// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/wanted_repository.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:consolarr/features/sonarr/data/wanted_repository.dart'
    show WantedScope;

/// The selected scope.
final wantedScopeProvider = NotifierProvider<WantedScopeNotifier, WantedScope>(
  WantedScopeNotifier.new,
);

class WantedScopeNotifier extends Notifier<WantedScope> {
  @override
  WantedScope build() => WantedScope.missing;

  void select(WantedScope scope) {
    if (scope != state) state = scope;
  }
}

/// The local series-title filter text (never sent anywhere).
final wantedFilterProvider = NotifierProvider<WantedFilterNotifier, String>(
  WantedFilterNotifier.new,
);

class WantedFilterNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String text) {
    if (text != state) state = text;
  }
}

/// Episodes of one series in the wanted list.
class WantedGroup {
  const WantedGroup({
    required this.seriesId,
    required this.series,
    required this.episodes,
  });

  final int seriesId;
  final SonarrSeries? series;
  final List<SonarrEpisode> episodes;
}

/// Groups by series, in first-seen order; episodes oldest air date first.
List<WantedGroup> groupBySeries(List<SonarrEpisode> episodes) {
  final byId = <int, List<SonarrEpisode>>{};
  for (final e in episodes) {
    byId.putIfAbsent(e.seriesId, () => []).add(e);
  }
  return [
    for (final entry in byId.entries)
      WantedGroup(
        seriesId: entry.key,
        series: entry.value.first.series,
        episodes: [...entry.value]
          ..sort(
            (a, b) => (a.airs ?? DateTime(0)).compareTo(b.airs ?? DateTime(0)),
          ),
      ),
  ];
}

sealed class WantedState {
  const WantedState();
}

final class WantedNoServer extends WantedState {
  const WantedNoServer();
}

final class WantedFailure extends WantedState {
  const WantedFailure(this.error);
  final AppError error;
}

/// Loaded episodes. [offlineError] marks a failed refresh: the list is what
/// was loaded before, and write actions are disabled.
final class WantedData extends WantedState {
  const WantedData({
    required this.scope,
    required this.episodes,
    required this.hasMore,
    required this.page,
    this.offlineError,
    this.loadMoreError,
    this.loadingMore = false,
  });

  final WantedScope scope;
  final List<SonarrEpisode> episodes;
  final bool hasMore;
  final int page;
  final AppError? offlineError;
  final AppError? loadMoreError;
  final bool loadingMore;

  bool get isOffline => offlineError != null;

  WantedData copyWith({
    List<SonarrEpisode>? episodes,
    bool? hasMore,
    int? page,
    AppError? offlineError,
    AppError? loadMoreError,
    bool? loadingMore,
    bool clearErrors = false,
  }) => WantedData(
    scope: scope,
    episodes: episodes ?? this.episodes,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
    offlineError: clearErrors ? null : (offlineError ?? this.offlineError),
    loadMoreError: clearErrors ? null : loadMoreError,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// The wanted list of the active server for the selected scope.
final wantedProvider = AsyncNotifierProvider<WantedNotifier, WantedState>(
  WantedNotifier.new,
  retry: (_, _) => null,
);

class WantedNotifier extends AsyncNotifier<WantedState> {
  WantedRepository? _repository;
  WantedScope _scope = WantedScope.missing;
  int _generation = 0;

  @override
  Future<WantedState> build() async {
    _generation++;
    _repository = null;
    _scope = ref.watch(wantedScopeProvider);
    final SonarrSession? session;
    try {
      session = await ref.watch(sonarrSessionProvider.future);
    } on AppError catch (error) {
      return WantedFailure(error);
    }
    if (session == null) return const WantedNoServer();
    final repository = WantedRepository(api: session.api, clock: session.clock);
    _repository = repository;
    final result = await repository.load(_scope);
    return result.when(
      ok: (p) => WantedData(
        scope: _scope,
        episodes: p.episodes,
        hasMore: p.hasMore,
        page: p.page,
      ),
      err: WantedFailure.new,
    );
  }

  /// Reloads; keeps the old list (marked offline) when the server is
  /// unreachable.
  Future<void> refresh() async {
    final repository = _repository;
    if (repository == null) {
      if (state.isLoading) return;
      ref.invalidateSelf();
      await future;
      return;
    }
    final generation = _generation;
    final previous = state.value;
    final result = await repository.load(_scope);
    if (!ref.mounted || generation != _generation) return;
    final error = result.errorOrNull;
    if (error != null) {
      if (previous is WantedData &&
          kOfflineFallbackCategories.contains(error.category)) {
        state = AsyncData(previous.copyWith(offlineError: error));
      } else {
        state = AsyncData(WantedFailure(error));
      }
      return;
    }
    final p = result.valueOrNull!;
    state = AsyncData(
      WantedData(
        scope: _scope,
        episodes: p.episodes,
        hasMore: p.hasMore,
        page: p.page,
      ),
    );
  }

  /// Appends the next page. Ignored while one is loading.
  Future<void> loadMore() async {
    final repository = _repository;
    final current = state.value;
    if (repository == null ||
        current is! WantedData ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final generation = _generation;
    state = AsyncData(current.copyWith(loadingMore: true));
    final result = await repository.load(_scope, page: current.page + 1);
    if (!ref.mounted || generation != _generation) return;
    final error = result.errorOrNull;
    if (error != null) {
      state = AsyncData(
        WantedData(
          scope: current.scope,
          episodes: current.episodes,
          hasMore: current.hasMore,
          page: current.page,
          loadMoreError: error,
        ),
      );
      return;
    }
    final p = result.valueOrNull!;
    final seen = {for (final e in current.episodes) e.id};
    state = AsyncData(
      WantedData(
        scope: current.scope,
        episodes: [
          ...current.episodes,
          for (final e in p.episodes)
            if (!seen.contains(e.id)) e,
        ],
        hasMore: p.hasMore,
        page: p.page,
      ),
    );
  }
}
