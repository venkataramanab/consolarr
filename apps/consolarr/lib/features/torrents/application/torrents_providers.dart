// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/torrents/application/poll_scheduler.dart';
import 'package:consolarr/features/torrents/application/speed_history.dart';
import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:consolarr/features/torrents/data/torrents_prefs.dart';
import 'package:consolarr/features/torrents/data/torrents_repository.dart';
import 'package:consolarr/shared/logging/log_events.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Preferences in `AppStateRows` (lazy; first read happens after the first
/// frame because only the torrent screen reads it).
final torrentsPrefsProvider = Provider<TorrentsPrefs>(
  (ref) => TorrentsPrefs(ref.watch(databaseProvider)),
);

/// The poll interval the user chose (seconds), persisted. `null` until read.
final torrentPollSecondsProvider =
    AsyncNotifierProvider<TorrentPollSeconds, int>(TorrentPollSeconds.new);

/// Default seconds between polls.
const defaultPollSeconds = 3;

/// The choices of the interval dialog.
const pollSecondsChoices = [1, 3, 5, 10, 30];

class TorrentPollSeconds extends AsyncNotifier<int> {
  @override
  Future<int> build() async =>
      await ref.watch(torrentsPrefsProvider).readPollSeconds() ??
      defaultPollSeconds;

  Future<void> choose(int seconds) async {
    state = AsyncData(seconds);
    try {
      await ref.read(torrentsPrefsProvider).writePollSeconds(seconds);
    } on Object {
      // Not persisted; the choice still applies for this session.
    }
  }
}

/// How often the visible list polls. Override in tests.
final torrentPollIntervalProvider = Provider<Duration>((ref) {
  final seconds = ref.watch(torrentPollSecondsProvider).value;
  return Duration(seconds: seconds ?? defaultPollSeconds);
});

/// The kind chosen in the server switcher (`torrents.selected_kind`), live.
/// `null` before any choice or when the preference cannot be read.
final selectedTorrentKindProvider = StreamProvider<ServiceKind?>((ref) {
  final stream = ref.watch(torrentsPrefsProvider).watchSelectedKind();
  return stream.handleError((Object _) {});
});

/// The client for the active torrent server, or `null` when none is
/// configured. The kind chosen in the switcher is tried first, then the
/// registered kinds in [torrentClientFactories] order; the first with an
/// active server wins. The session (cookie, token) lives inside the client, in
/// memory only, and is forgotten when the active server changes or the
/// provider is disposed. Fails like `activeConnectionProvider` (for example
/// `needs_credentials`).
final torrentClientProvider = FutureProvider<TorrentClient?>(retry: _noRetry, (
  ref,
) async {
  ServiceKind? selected;
  try {
    selected = await ref.watch(selectedTorrentKindProvider.future);
  } on Object {
    selected = null;
  }
  final order = [
    if (selected != null && torrentClientFactories.containsKey(selected))
      selected,
    for (final k in torrentClientFactories.keys)
      if (k != selected) k,
  ];
  for (final kind in order) {
    final connection = await ref.watch(activeConnectionProvider(kind).future);
    if (connection == null) continue;
    final profile = connection.profile;
    final credentials = await ref
        .watch(serverRepositoryProvider)
        .loadCredentials(profile);
    final prefs = ref.read(torrentsPrefsProvider);
    final client = torrentClientFactories[kind]!(
      TorrentClientContext(
        dio: connection.dio,
        profile: profile,
        credentials: credentials,
        hostId: await prefs.readDelugeHost(profile.id),
        onHostConnected: (id) => prefs.writeDelugeHost(profile.id, id),
        onRowsSkipped: (count) => ref
            .read(loggerProvider)
            .info('skipped $count malformed torrent rows'),
      ),
    );
    ref.onDispose(client.forgetSession);
    return client;
  }
  return null;
});

/// The controls the current client supports (defaults while loading).
final torrentCapabilitiesProvider = Provider<TorrentCapabilities>((ref) {
  // Re-evaluated after every list result: detection (Deluge's label plugin)
  // completes during the first list call.
  final list = ref.watch(torrentListProvider);
  final client = ref.watch(torrentClientProvider);
  if (list.isLoading || client.isLoading || client.hasError) {
    return const TorrentCapabilities();
  }
  return client.value?.capabilities ?? const TorrentCapabilities();
});

/// What the torrent list screen shows (sealed, like every feature state).
///
/// "Nothing could be loaded" is not a state here: it is the provider's
/// `AsyncError` carrying the [AppError] (with its category), so the screen can
/// tell unauthorized from unreachable.
sealed class TorrentListState {
  const TorrentListState();
}

/// No torrent client is configured.
final class TorrentsNoServer extends TorrentListState {
  const TorrentsNoServer();
}

/// The torrents of the active server, live or (after a reachability failure)
/// the last good copy.
final class TorrentsData extends TorrentListState {
  const TorrentsData({
    required this.torrents,
    this.transfer,
    this.fetchedAt,
    this.offlineError,
    this.transferUnavailable = false,
  });

  final List<Torrent> torrents;
  final TransferInfo? transfer;

  /// When [torrents] were last read successfully.
  final DateTime? fetchedAt;

  /// The last poll failed with a reachability category; [torrents] is the last
  /// good data. Other failures (for example `auth_failed`) are not kept as
  /// offline: they replace the state with an error.
  final AppError? offlineError;

  /// Torrents loaded but the statistics did not (partial).
  final bool transferUnavailable;

  bool get offline => offlineError != null;

  TorrentsData withOfflineError(AppError error) => TorrentsData(
    torrents: torrents,
    transfer: transfer,
    fetchedAt: fetchedAt,
    offlineError: error,
    transferUnavailable: transferUnavailable,
  );
}

/// The torrent list. `AsyncError` (an [AppError]) means nothing could be
/// loaded, or that a refresh failed for a reason that must not be hidden
/// behind old data ([kOfflineFallbackCategories] decides). While the active
/// server changes the value is `AsyncLoading`; screens must check
/// `isLoading` and `hasError` before reading `value`, because Riverpod keeps
/// the previous server's value through reloads and errors.
final torrentListProvider =
    AsyncNotifierProvider<TorrentListNotifier, TorrentListState>(
      TorrentListNotifier.new,
      // The screen polls and offers retry; no hidden automatic retries.
      retry: _noRetry,
    );

Duration? _noRetry(int retryCount, Object error) => null;

class TorrentListNotifier extends AsyncNotifier<TorrentListState> {
  /// Bumped by every build (a server switch or credential edit rebuilds), so
  /// results of work started for an earlier build can be recognised and
  /// dropped.
  int _generation = 0;
  int? _inFlightGeneration;

  @override
  Future<TorrentListState> build() async {
    _generation++;
    consecutiveFailures = 0;
    final client = await ref.watch(torrentClientProvider.future);
    if (client == null) return const TorrentsNoServer();
    final result = await _fetch(client);
    // A superseded build's value is discarded by Riverpod itself.
    return result.when(ok: (s) => s, err: (e) => throw e);
  }

  Future<Result<TorrentsData>> _fetch(TorrentClient client) async {
    final snapshot = await TorrentsRepository(
      client,
      clock: ref.read(clockProvider),
    ).fetch();
    return snapshot.map(
      (s) => TorrentsData(
        torrents: s.torrents,
        transfer: s.transfer,
        fetchedAt: s.fetchedAt,
        transferUnavailable: s.transfer == null,
      ),
    );
  }

  /// Failures in a row since the last good read (drives the back-off).
  int consecutiveFailures = 0;

  /// Re-reads the client. Keeps existing data on a reachability failure
  /// (offline); other failures become the provider's error. Overlapping calls
  /// are coalesced, a refresh during a reload is ignored, and a result that
  /// arrives after the connection changed (or the provider was disposed) is
  /// dropped.
  ///
  /// With [quiet] (background polls) the first failures keep the list as it is
  /// and only the [pollFailuresUntilOffline]th marks it offline; a user action
  /// (pull to refresh, "Reconnect") reports at once. Returns `false` when the
  /// read failed.
  Future<bool> refresh({bool quiet = false}) async {
    final generation = _generation;
    if (_inFlightGeneration == generation) return true;
    final current = state;
    // Mid-reload the visible value belongs to the previous server.
    if (current.isLoading) return true;
    _inFlightGeneration = generation;
    bool stale() => !ref.mounted || generation != _generation;
    try {
      final previous = current is AsyncData<TorrentListState>
          ? current.value
          : null;
      final TorrentClient? client;
      try {
        client = await ref.read(torrentClientProvider.future);
      } on Object catch (e) {
        if (!stale()) _fail(previous, appErrorOrUnknown(e), quiet: quiet);
        return false;
      }
      if (stale()) return true;
      if (client == null) {
        state = const AsyncData(TorrentsNoServer());
        return true;
      }
      final result = await _fetch(client);
      if (stale()) return true;
      final ok = result.when(
        ok: (s) {
          consecutiveFailures = 0;
          state = AsyncData(s);
          return true;
        },
        err: (e) {
          _fail(previous, e, quiet: quiet);
          return false;
        },
      );
      return ok;
    } finally {
      if (_inFlightGeneration == generation) _inFlightGeneration = null;
    }
  }

  void _fail(TorrentListState? previous, AppError error, {bool quiet = false}) {
    consecutiveFailures++;
    final canFallBack =
        previous is TorrentsData &&
        kOfflineFallbackCategories.contains(error.category);
    if (canFallBack) {
      if (quiet &&
          !previous.offline &&
          consecutiveFailures < pollFailuresUntilOffline) {
        return; // keep showing the data; the scheduler backs off
      }
      logOfflineFallback(ref.read(loggerProvider), OfflineArea.torrents, error);
      state = AsyncData(previous.withOfflineError(error));
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
    if (data is! TorrentsData || data.offline) return null;
    final transfer = data.transfer;
    if (transfer == null) return null;
    return SpeedSample(down: transfer.dlSpeed, up: transfer.upSpeed);
  }

  @override
  List<SpeedSample> build() {
    ref.listen(torrentListProvider, (previous, next) {
      // A server switch reloads the list: the old server's speeds must not
      // linger in the graph.
      if (next.isLoading || next.hasError) {
        state = const [];
        return;
      }
      final data = next.value;
      // Only a new poll adds a sample, not a rebuild of the same value.
      if (identical(previous?.value, data)) return;
      final sample = _sampleOf(data);
      if (sample != null) state = appendSpeedSample(state, sample);
    });
    final initial = ref.read(torrentListProvider);
    final first = initial.isLoading || initial.hasError
        ? null
        : _sampleOf(initial.value);
    return first == null ? const [] : [first];
  }
}
