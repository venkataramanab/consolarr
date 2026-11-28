// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// The limits sheet's state: what the client reports, plus what is running.
class LimitsView {
  const LimitsView({
    required this.limits,
    this.applying = false,
    this.failure,
    this.applied = false,
    this.altUnsupported = false,
  });

  final SpeedLimitsState limits;
  final bool applying;
  final AppError? failure;

  /// The last apply succeeded.
  final bool applied;

  /// The server refused the alternative-limits call (older version).
  final bool altUnsupported;

  LimitsView copyWith({
    SpeedLimitsState? limits,
    bool? applying,
    AppError? failure,
    bool clearFailure = false,
    bool? applied,
    bool? altUnsupported,
  }) => LimitsView(
    limits: limits ?? this.limits,
    applying: applying ?? this.applying,
    failure: clearFailure ? null : failure ?? this.failure,
    applied: applied ?? this.applied,
    altUnsupported: altUnsupported ?? this.altUnsupported,
  );
}

/// Global limits (TOR-10): loaded when the sheet opens, applied on request.
final torrentLimitsProvider =
    AsyncNotifierProvider.autoDispose<TorrentLimitsController, LimitsView>(
      TorrentLimitsController.new,
      retry: (_, _) => null,
    );

class TorrentLimitsController extends AsyncNotifier<LimitsView> {
  /// Bumped by every build (a client switch rebuilds), so work started for an
  /// earlier build is dropped when it completes.
  int _generation = 0;

  @override
  Future<LimitsView> build() async {
    _generation++;
    final c = await ref.watch(torrentClientProvider.future);
    if (c == null) throw const AppError(ErrorCategory.notFound);
    final r = await c.globalLimits();
    return r.when(
      ok: (l) => LimitsView(limits: l),
      err: (e) => throw e,
    );
  }

  void _track(TorrentClient client, Result<void> r) {
    final kind = ServiceKindParam.fromCode(client.kind.name);
    if (kind == null) return;
    unawaited(
      ref
          .read(eventTrackerProvider)
          .track(
            TorrentsSpeedLimitsChangedEvent(
              client: kind,
              outcome: r.isOk
                  ? TorrentOutcomeParam.success
                  : UnsupportedAction.isIt(r.errorOrNull!)
                  ? TorrentOutcomeParam.unsupported
                  : TorrentOutcomeParam.failed,
            ),
          ),
    );
  }

  /// Runs [call] on the client of this build. Returns `null` (and does
  /// nothing) when there is no client, or when the client or the build changed
  /// while the call was in flight: its result belongs to the old server.
  Future<({TorrentClient client, Result<void> result})?> _guarded(
    Future<Result<void>> Function(TorrentClient client) call,
  ) async {
    final generation = _generation;
    final client = ref.read(torrentClientProvider).value;
    if (client == null) return null;
    final result = await call(client);
    if (!ref.mounted ||
        generation != _generation ||
        !identical(client, ref.read(torrentClientProvider).value)) {
      return null;
    }
    return (client: client, result: result);
  }

  /// Applies [download] and [upload] (bytes per second, 0 = unlimited), then
  /// re-reads what the server stored (clients round, for example to kB/s).
  Future<void> apply({required int download, required int upload}) async {
    final current = state.value;
    if (current == null || current.applying) return;
    state = AsyncData(
      current.copyWith(applying: true, clearFailure: true, applied: false),
    );
    final done = await _guarded(
      (c) =>
          c.setGlobalLimits(GlobalLimits(download: download, upload: upload)),
    );
    if (done == null) return;
    _track(done.client, done.result);
    final error = done.result.errorOrNull;
    if (error != null) {
      state = AsyncData(current.copyWith(applying: false, failure: error));
      return;
    }
    final generation = _generation;
    final reread = await done.client.globalLimits();
    if (!ref.mounted ||
        generation != _generation ||
        !identical(done.client, ref.read(torrentClientProvider).value)) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        // What the server reports; the requested values when the re-read fails.
        limits: reread.when(
          ok: (l) => l,
          err: (_) => SpeedLimitsState(
            download: download,
            upload: upload,
            alternativeActive: current.limits.alternativeActive,
          ),
        ),
        applying: false,
        applied: true,
      ),
    );
    unawaited(ref.read(torrentListProvider.notifier).refresh());
  }

  Future<void> setAlternative(bool enabled) async {
    final current = state.value;
    if (current == null || current.applying) return;
    state = AsyncData(
      current.copyWith(applying: true, clearFailure: true, applied: false),
    );
    final done = await _guarded((c) => c.setAlternativeSpeed(enabled));
    if (done == null) return;
    _track(done.client, done.result);
    final error = done.result.errorOrNull;
    final unsupported = error != null && UnsupportedAction.isIt(error);
    state = AsyncData(
      error == null
          ? current.copyWith(
              limits: SpeedLimitsState(
                download: current.limits.download,
                upload: current.limits.upload,
                alternativeActive: enabled,
              ),
              applying: false,
            )
          : current.copyWith(
              applying: false,
              failure: unsupported ? null : error,
              altUnsupported: unsupported,
            ),
    );
  }
}
