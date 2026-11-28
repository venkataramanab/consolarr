// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// What a row is waiting for (optimistic state, reverted on failure).
enum PendingAction { pausing, resuming, removing }

/// Pause all / resume all in progress.
enum BulkAction { pauseAll, resumeAll }

class TorrentActionsState {
  const TorrentActionsState({this.rows = const {}, this.bulk, this.bulkCount});

  final Map<String, PendingAction> rows;
  final BulkAction? bulk;
  final int? bulkCount;
}

/// Pause, resume and remove (TOR-06, TOR-07). Every method returns a
/// [Result]; a failure puts the row back (the pending marker is only a label)
/// and the screen shows the reason. The list is re-read after every outcome.
/// A bulk or removal where only some torrents failed (Deluge) returns a
/// `PartialActionFailure`; the screen reports "N of M". The state resets when
/// the client changes.
final torrentActionsProvider =
    NotifierProvider<TorrentActionsController, TorrentActionsState>(
      TorrentActionsController.new,
    );

class TorrentActionsController extends Notifier<TorrentActionsState> {
  /// Bumped by every build (a server switch rebuilds and resets the state), so
  /// an action started for an earlier build never touches the new state.
  int _generation = 0;

  @override
  TorrentActionsState build() {
    // A server switch drops every pending marker of the previous server.
    _generation++;
    ref.watch(torrentClientProvider);
    return const TorrentActionsState();
  }

  Future<TorrentClient?> _client() async {
    try {
      return await ref.read(torrentClientProvider.future);
    } on Object {
      return null;
    }
  }

  void _track(TorrentActionParam action, Result<void> r, TorrentClient c) {
    final outcome = r.when(
      ok: (_) => TorrentOutcomeParam.success,
      err: (e) => UnsupportedAction.isIt(e)
          ? TorrentOutcomeParam.unsupported
          : TorrentOutcomeParam.failed,
    );
    unawaited(
      ref
          .read(eventTrackerProvider)
          .track(TorrentsActionEvent(action: action, outcome: outcome)),
    );
    if (r case Err<void>(:final error)) {
      final category = ErrorCategoryParam.fromCode(error.category.code);
      final service = ServiceKindParam.fromCode(c.kind.name);
      if (category != null && service != null) {
        ref
            .read(breadcrumbsProvider)
            .add(Breadcrumb.apiError(category, service));
      }
    }
  }

  Future<Result<void>> _row(
    String hash,
    PendingAction pending,
    TorrentActionParam event,
    Future<Result<void>> Function(TorrentClient c) run,
  ) async {
    if (state.rows.containsKey(hash)) {
      return const Result.err(AppError(ErrorCategory.serverError));
    }
    final client = await _client();
    if (client == null || !ref.mounted) {
      return const Result.err(AppError(ErrorCategory.networkUnreachable));
    }
    final generation = _generation;
    state = TorrentActionsState(
      rows: {...state.rows, hash: pending},
      bulk: state.bulk,
      bulkCount: state.bulkCount,
    );
    final result = await run(client);
    if (!ref.mounted || generation != _generation) return result;
    _track(event, result, client);
    // Also after a failure: a partial failure changed some torrents, and a
    // dropped connection may have applied the action anyway.
    await ref.read(torrentListProvider.notifier).refresh();
    if (!ref.mounted || generation != _generation) return result;
    final rows = {...state.rows}..remove(hash);
    state = TorrentActionsState(
      rows: rows,
      bulk: state.bulk,
      bulkCount: state.bulkCount,
    );
    return result;
  }

  Future<Result<void>> pause(String hash) => _row(
    hash,
    PendingAction.pausing,
    TorrentActionParam.pause,
    (c) => c.pause([hash]),
  );

  Future<Result<void>> resume(String hash) => _row(
    hash,
    PendingAction.resuming,
    TorrentActionParam.resume,
    (c) => c.resume([hash]),
  );

  Future<Result<void>> remove(String hash, {required bool deleteFiles}) => _row(
    hash,
    PendingAction.removing,
    deleteFiles ? TorrentActionParam.removeWithData : TorrentActionParam.remove,
    (c) => c.delete([hash], deleteFiles: deleteFiles),
  );

  Future<Result<void>> _bulk(
    BulkAction action,
    List<String> hashes,
    TorrentActionParam event,
    Future<Result<void>> Function(TorrentClient c, List<String> h) run,
  ) async {
    if (state.bulk != null || hashes.isEmpty) {
      return const Result.ok(null);
    }
    final client = await _client();
    if (client == null || !ref.mounted) {
      return const Result.err(AppError(ErrorCategory.networkUnreachable));
    }
    final generation = _generation;
    state = TorrentActionsState(
      rows: state.rows,
      bulk: action,
      bulkCount: hashes.length,
    );
    final result = await run(client, hashes);
    if (!ref.mounted || generation != _generation) return result;
    _track(event, result, client);
    await ref.read(torrentListProvider.notifier).refresh();
    if (!ref.mounted || generation != _generation) return result;
    state = TorrentActionsState(rows: state.rows);
    return result;
  }

  Future<Result<void>> pauseAll(List<String> hashes) => _bulk(
    BulkAction.pauseAll,
    hashes,
    TorrentActionParam.pauseAll,
    (c, h) => c.pause(h),
  );

  Future<Result<void>> resumeAll(List<String> hashes) => _bulk(
    BulkAction.resumeAll,
    hashes,
    TorrentActionParam.resumeAll,
    (c, h) => c.resume(h),
  );
}
