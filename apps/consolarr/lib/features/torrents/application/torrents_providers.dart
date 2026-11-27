// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/data/torrents_repository.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// How often the visible list polls. Override in tests.
final torrentPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// The qBittorrent client for the active torrent server, or `null` when none
/// is configured. The session cookie lives inside the client (memory only) and
/// is forgotten when the active server changes or the provider is disposed.
/// Fails like `activeConnectionProvider` (for example `needs_credentials`).
final torrentClientProvider = FutureProvider<TorrentClient?>(retry: _noRetry, (
  ref,
) async {
  final connection = await ref.watch(
    activeConnectionProvider(ServiceKind.qbittorrent).future,
  );
  if (connection == null) return null;
  final profile = connection.profile;
  final credentials = profile.authMode == AuthMode.basic
      ? await ref.watch(serverRepositoryProvider).loadCredentials(profile)
      : null;
  final client = QBittorrentClient(
    dio: connection.dio,
    username: credentials?.username,
    password: credentials?.password,
  );
  ref.onDispose(client.forgetSession);
  return client;
});

/// What the torrent list screen shows.
class TorrentListState {
  const TorrentListState({
    this.torrents = const [],
    this.transfer,
    this.fetchedAt,
    this.noServer = false,
    this.offline = false,
    this.transferUnavailable = false,
  });

  /// No torrent client is configured.
  const TorrentListState.noServer() : this(noServer: true);

  final List<Torrent> torrents;
  final TransferInfo? transfer;

  /// When [torrents] were last read successfully.
  final DateTime? fetchedAt;
  final bool noServer;

  /// The last poll failed; [torrents] is the last good data.
  final bool offline;

  /// Torrents loaded but the statistics did not (partial).
  final bool transferUnavailable;

  TorrentListState copyWith({bool? offline}) => TorrentListState(
    torrents: torrents,
    transfer: transfer,
    fetchedAt: fetchedAt,
    noServer: noServer,
    offline: offline ?? this.offline,
    transferUnavailable: transferUnavailable,
  );
}

/// The torrent list. `AsyncError` (an [AppError]) means nothing could be
/// loaded yet; once data exists a failing refresh keeps it and sets
/// [TorrentListState.offline] instead.
final torrentListProvider =
    AsyncNotifierProvider<TorrentListNotifier, TorrentListState>(
      TorrentListNotifier.new,
      // The screen polls and offers retry; no hidden automatic retries.
      retry: _noRetry,
    );

Duration? _noRetry(int retryCount, Object error) => null;

class TorrentListNotifier extends AsyncNotifier<TorrentListState> {
  bool _inFlight = false;

  @override
  Future<TorrentListState> build() async {
    final client = await ref.watch(torrentClientProvider.future);
    if (client == null) return const TorrentListState.noServer();
    final result = await _fetch(client);
    return result.when(ok: (s) => s, err: (e) => throw e);
  }

  Future<Result<TorrentListState>> _fetch(TorrentClient client) async {
    final snapshot = await TorrentsRepository(
      client,
      clock: ref.read(clockProvider),
    ).fetch();
    return snapshot.map(
      (s) => TorrentListState(
        torrents: s.torrents,
        transfer: s.transfer,
        fetchedAt: s.fetchedAt,
        transferUnavailable: s.transfer == null,
      ),
    );
  }

  /// Re-reads the client. Keeps existing data on failure (offline); without
  /// data the failure becomes the provider's error. Overlapping calls are
  /// coalesced.
  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final previous = state.value;
      final TorrentClient? client;
      try {
        client = await ref.read(torrentClientProvider.future);
      } on Object catch (e) {
        _fail(previous, appErrorOrUnknown(e));
        return;
      }
      if (client == null) {
        state = const AsyncData(TorrentListState.noServer());
        return;
      }
      final result = await _fetch(client);
      result.when(
        ok: (s) => state = AsyncData(s),
        err: (e) => _fail(previous, e),
      );
    } finally {
      _inFlight = false;
    }
  }

  void _fail(TorrentListState? previous, AppError error) {
    if (previous != null && !previous.noServer) {
      state = AsyncData(previous.copyWith(offline: true));
    } else {
      state = AsyncError(error, StackTrace.current);
    }
  }
}

/// [e] as an [AppError] (anything else is reported as unreachable).
AppError appErrorOrUnknown(Object e) =>
    e is AppError ? e : const AppError(ErrorCategory.networkUnreachable);

/// Rolling window of the last global speeds, fed by successful polls.
final speedHistoryProvider =
    NotifierProvider<SpeedHistoryNotifier, List<SpeedSample>>(
      SpeedHistoryNotifier.new,
    );

class SpeedHistoryNotifier extends Notifier<List<SpeedSample>> {
  static SpeedSample? _sampleOf(TorrentListState? data) {
    final transfer = data?.transfer;
    if (data == null || data.offline || transfer == null) return null;
    return SpeedSample(down: transfer.dlSpeed, up: transfer.upSpeed);
  }

  @override
  List<SpeedSample> build() {
    ref.listen(torrentListProvider, (previous, next) {
      final data = next.value;
      // Only a new poll adds a sample, not a rebuild of the same value.
      if (identical(previous?.value, data)) return;
      final sample = _sampleOf(data);
      if (sample != null) state = appendSpeedSample(state, sample);
    });
    final first = _sampleOf(ref.read(torrentListProvider).value);
    return first == null ? const [] : [first];
  }
}
