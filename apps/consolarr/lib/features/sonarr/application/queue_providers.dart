// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/queue_repository.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';

/// What the queue tab shows.
sealed class QueueState {
  const QueueState();
}

/// No Sonarr server is configured.
final class QueueNoServer extends QueueState {
  const QueueNoServer();
}

/// Nothing to show: the first load failed (or a non-recoverable error such as
/// `auth_failed` replaced the list).
final class QueueFailure extends QueueState {
  const QueueFailure(this.error);
  final AppError error;
}

/// The queue (possibly empty). With [offlineError] set the list is the last
/// one read at [fetchedAt] and the refresh failed: writes are disabled.
final class QueueData extends QueueState {
  const QueueData(this.items, {required this.fetchedAt, this.offlineError});

  final List<ArrQueueItem> items;
  final DateTime fetchedAt;
  final AppError? offlineError;

  bool get isOffline => offlineError != null;
}

/// How often a visible queue refreshes itself.
final queuePollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// The Sonarr queue. Auto-disposed: leaving the tab ends the polling timer.
/// A server switch rebuilds it (it watches the session), so screens check
/// `isLoading` and `hasError` before `value`.
final queueProvider =
    AsyncNotifierProvider.autoDispose<QueueNotifier, QueueState>(
      QueueNotifier.new,
    );

class QueueNotifier extends AsyncNotifier<QueueState> {
  SonarrQueueRepository? _repository;
  Timer? _timer;
  int _generation = 0;
  bool _visible = true;
  bool _refreshing = false;
  final Set<int> _removing = {};

  @override
  Future<QueueState> build() async {
    _generation++;
    _repository = null;
    _timer?.cancel();
    final SonarrSession? session;
    try {
      session = await ref.watch(sonarrSessionProvider.future);
    } on AppError catch (error) {
      return QueueFailure(error);
    }
    if (session == null) return const QueueNoServer();
    final repository = SonarrQueueRepository(api: session.api);
    _repository = repository;
    final now = ref.watch(clockProvider);
    final result = await repository.load();
    final interval = ref.read(queuePollIntervalProvider);
    _timer = Timer.periodic(interval, (_) => unawaited(_poll()));
    ref.onDispose(() => _timer?.cancel());
    return result.when(
      ok: (items) => QueueData(items, fetchedAt: now()),
      err: QueueFailure.new,
    );
  }

  /// The screen reports whether it is on screen; hidden queues do not poll.
  set visible(bool value) => _visible = value;

  bool get _foreground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  Future<void> _poll() async {
    if (!_visible || !_foreground) return;
    await refresh();
  }

  /// Reloads the queue, keeping the visible list when the server cannot be
  /// reached. A result for an older connection is dropped.
  Future<void> refresh() async {
    final repository = _repository;
    if (repository == null) {
      if (state.isLoading) return;
      ref.invalidateSelf();
      await future;
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final result = await repository.load();
      if (!ref.mounted || generation != _generation) return;
      _apply(result);
    } finally {
      _refreshing = false;
    }
  }

  void _apply(Result<List<ArrQueueItem>> result) {
    final now = ref.read(clockProvider)();
    final previous = state.value;
    final error = result.errorOrNull;
    if (error == null) {
      state = AsyncData(QueueData(result.valueOrNull!, fetchedAt: now));
    } else if (previous is QueueData &&
        kOfflineFallbackCategories.contains(error.category)) {
      state = AsyncData(
        QueueData(
          previous.items,
          fetchedAt: previous.fetchedAt,
          offlineError: error,
        ),
      );
    } else {
      state = AsyncData(QueueFailure(error));
    }
  }

  /// Removes a queue item (SON-15). Returns null on success or the error.
  ///
  /// One request per item at a time. After a failure the queue is re-read
  /// first: when the item is gone the request did land (a dropped connection
  /// after the server acted), so it counts as success rather than inviting a
  /// second submit.
  Future<AppError?> remove(int id, ArrQueueRemovalChoice choice) async {
    final repository = _repository;
    final current = state.value;
    if (repository == null || current is! QueueData) {
      return const AppError(ErrorCategory.networkUnreachable);
    }
    if (current.isOffline) return current.offlineError;
    if (!_removing.add(id)) return null;
    final generation = _generation;
    try {
      final result = await repository.remove(
        id,
        removeFromClient: choice.removeFromClient,
        blocklist: choice.blocklist,
      );
      if (!ref.mounted || generation != _generation) return null;
      final error = result.errorOrNull;
      if (error != null) {
        final reread = await repository.load();
        if (!ref.mounted || generation != _generation) return null;
        final items = reread.valueOrNull;
        if (items == null || items.any((i) => i.id == id)) return error;
        _apply(reread);
      } else {
        _apply(
          Result.ok([
            for (final i in current.items)
              if (i.id != id) i,
          ]),
        );
        unawaited(refresh());
      }
      ref
          .read(eventTrackerProvider)
          .track(
            QueueItemRemovedEvent(
              blocklist: switch (choice.blocklist) {
                ArrBlocklistChoice.none => SonarrBlocklistChoiceParam.none,
                ArrBlocklistChoice.blocklistAndSearch =>
                  SonarrBlocklistChoiceParam.blocklistAndSearch,
                ArrBlocklistChoice.blocklistOnly =>
                  SonarrBlocklistChoiceParam.blocklistOnly,
              },
              fromClient: choice.removeFromClient,
            ),
          );
      return null;
    } finally {
      _removing.remove(id);
    }
  }
}
