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
  Future<TorrentClient> _client() async {
    final c = await ref.watch(torrentClientProvider.future);
    if (c == null) throw const AppError(ErrorCategory.notFound);
    return c;
  }

  @override
  Future<LimitsView> build() async {
    final client = await _client();
    final r = await client.globalLimits();
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
            SpeedLimitsChangedEvent(
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

  /// Applies [download] and [upload] (bytes per second, 0 = unlimited).
  Future<void> apply({required int download, required int upload}) async {
    final current = state.value;
    if (current == null || current.applying) return;
    state = AsyncData(
      current.copyWith(applying: true, clearFailure: true, applied: false),
    );
    final client = await _client();
    final r = await client.setGlobalLimits(
      GlobalLimits(download: download, upload: upload),
    );
    if (!ref.mounted) return;
    _track(client, r);
    state = AsyncData(
      r.when(
        ok: (_) => current.copyWith(
          limits: SpeedLimitsState(
            download: download,
            upload: upload,
            alternativeActive: current.limits.alternativeActive,
          ),
          applying: false,
          applied: true,
        ),
        err: (e) => current.copyWith(applying: false, failure: e),
      ),
    );
    if (r.isOk) unawaited(ref.read(torrentListProvider.notifier).refresh());
  }

  Future<void> setAlternative(bool enabled) async {
    final current = state.value;
    if (current == null || current.applying) return;
    state = AsyncData(
      current.copyWith(applying: true, clearFailure: true, applied: false),
    );
    final client = await _client();
    final r = await client.setAlternativeSpeed(enabled);
    if (!ref.mounted) return;
    _track(client, r);
    final unsupported =
        r.errorOrNull != null && UnsupportedAction.isIt(r.errorOrNull!);
    state = AsyncData(
      r.when(
        ok: (_) => current.copyWith(
          limits: SpeedLimitsState(
            download: current.limits.download,
            upload: current.limits.upload,
            alternativeActive: enabled,
          ),
          applying: false,
        ),
        err: (e) => current.copyWith(
          applying: false,
          failure: unsupported ? null : e,
          altUnsupported: unsupported,
        ),
      ),
    );
  }
}
