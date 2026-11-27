// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/data/detail_repository.dart';
import 'package:consolarr/src/images/secure_image_provider.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:observability/observability.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:consolarr/features/sonarr/data/detail_repository.dart'
    show DetailSnapshot;

/// What the series detail screen shows (NAV-05 included).
sealed class DetailState {
  const DetailState();
}

/// No Sonarr server is configured.
final class DetailNoServer extends DetailState {
  const DetailNoServer();
}

/// The series does not exist (any more): "no longer exists" message.
final class DetailGone extends DetailState {
  const DetailGone();
}

/// The series, live or cached, plus the state of the toggles in flight.
final class DetailData extends DetailState {
  const DetailData(
    this.snapshot, {
    this.pendingEpisodes = const {},
    this.failedEpisodes = const {},
    this.pendingSeasons = const {},
    this.failedSeasons = const {},
  });

  final DetailSnapshot snapshot;

  /// Episode ids whose toggle is being saved.
  final Set<int> pendingEpisodes;

  /// Episode id -> the monitored value that could not be saved (retry).
  final Map<int, bool> failedEpisodes;
  final Set<int> pendingSeasons;
  final Map<int, bool> failedSeasons;

  bool get isOffline => snapshot.isOffline;

  DetailData copyWith({
    DetailSnapshot? snapshot,
    Set<int>? pendingEpisodes,
    Map<int, bool>? failedEpisodes,
    Set<int>? pendingSeasons,
    Map<int, bool>? failedSeasons,
  }) => DetailData(
    snapshot ?? this.snapshot,
    pendingEpisodes: pendingEpisodes ?? this.pendingEpisodes,
    failedEpisodes: failedEpisodes ?? this.failedEpisodes,
    pendingSeasons: pendingSeasons ?? this.pendingSeasons,
    failedSeasons: failedSeasons ?? this.failedSeasons,
  );
}

/// One series. Failures that block the screen are the provider's own
/// `AsyncError` (an [AppError]); screens check `isLoading`, then `hasError`,
/// then `value`, because Riverpod keeps the previous series through reloads.
final seriesDetailProvider = AsyncNotifierProvider.autoDispose
    .family<SeriesDetailNotifier, DetailState, int>(
      SeriesDetailNotifier.new,
      retry: (_, _) => null,
    );

class SeriesDetailNotifier extends AsyncNotifier<DetailState> {
  SeriesDetailNotifier(this.seriesId);

  final int seriesId;
  DetailRepository? _repository;
  SonarrApi? _api;

  /// Bumped by every build; stale results compare it after each await.
  int _generation = 0;

  @override
  Future<DetailState> build() async {
    _generation++;
    _repository = null;
    _api = null;
    if (seriesId < 0) return const DetailGone();
    final session = await ref.watch(sonarrSessionProvider.future);
    if (session == null) return const DetailNoServer();
    final repository = DetailRepository(
      api: session.api,
      cache: session.cache,
      serverId: session.serverId,
      clock: session.clock,
    );
    _repository = repository;
    _api = session.api;
    return _toState(await repository.load(seriesId));
  }

  DetailState _toState(Result<DetailSnapshot> result) {
    final error = result.errorOrNull;
    if (error == null) return DetailData(result.valueOrNull!);
    if (error.category == ErrorCategory.notFound) return const DetailGone();
    throw error;
  }

  /// Reloads without clearing the screen; a failure keeps what is shown and
  /// marks it offline when the category allows it.
  Future<void> refresh() async {
    final repository = _repository;
    final generation = _generation;
    final current = state.value;
    if (repository == null || state.isLoading) {
      ref.invalidateSelf();
      await future;
      return;
    }
    final result = await repository.load(seriesId);
    if (!ref.mounted || generation != _generation) return;
    final error = result.errorOrNull;
    if (error != null &&
        current is DetailData &&
        error.category != ErrorCategory.notFound &&
        kOfflineFallbackCategories.contains(error.category)) {
      state = AsyncData(
        current.copyWith(
          snapshot: current.snapshot.copyWith(offlineError: error),
        ),
      );
      return;
    }
    try {
      state = AsyncData(_toState(result));
    } on AppError catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  /// Re-reads the episodes only (retry of the episode list).
  Future<void> reloadEpisodes() async {
    final data = _data;
    final repository = _repository;
    if (data == null || repository == null) return;
    final generation = _generation;
    final result = await repository.reloadEpisodes(data.snapshot);
    final next = result.valueOrNull;
    if (!ref.mounted || generation != _generation || next == null) return;
    state = AsyncData(_data!.copyWith(snapshot: next));
  }

  DetailData? get _data {
    final s = state.value;
    return s is DetailData ? s : null;
  }

  /// Sets the monitored flag of one episode. Optimistic; a failure is shown
  /// on the row with a retry. Disabled offline.
  Future<void> setEpisodeMonitored(
    int episodeId, {
    required bool monitored,
  }) async {
    final data = _data;
    final api = _api;
    if (data == null || api == null || data.isOffline) return;
    if (data.pendingEpisodes.contains(episodeId)) return;
    final generation = _generation;
    final failed = {...data.failedEpisodes}..remove(episodeId);
    state = AsyncData(
      data.copyWith(
        snapshot: _withEpisode(data.snapshot, episodeId, monitored),
        pendingEpisodes: {...data.pendingEpisodes, episodeId},
        failedEpisodes: failed,
      ),
    );
    final result = await api.setEpisodesMonitored([
      episodeId,
    ], monitored: monitored);
    if (!ref.mounted || generation != _generation) return;
    final now = _data!;
    final ok = result.isOk;
    final next = now.copyWith(
      // A failed change goes back to what the server has.
      snapshot: ok
          ? now.snapshot
          : _withEpisode(now.snapshot, episodeId, !monitored),
      pendingEpisodes: {...now.pendingEpisodes}..remove(episodeId),
      failedEpisodes: ok
          ? now.failedEpisodes
          : {...now.failedEpisodes, episodeId: monitored},
    );
    state = AsyncData(next);
    if (ok) {
      ref
          .read(eventTrackerProvider)
          .track(SeriesMonitorChangedEvent(monitored: monitored));
      await _repository?.store(next.snapshot);
    }
  }

  DetailSnapshot _withEpisode(DetailSnapshot s, int id, bool monitored) =>
      s.copyWith(
        episodes: [
          for (final e in s.episodes)
            if (e.id == id) e.copyWith(monitored: monitored) else e,
        ],
      );

  /// Sets the monitored flag of a whole season through the series resource.
  Future<void> setSeasonMonitored(int season, {required bool monitored}) async {
    final data = _data;
    final api = _api;
    if (data == null || api == null || data.isOffline) return;
    if (data.pendingSeasons.contains(season)) return;
    final generation = _generation;
    state = AsyncData(
      data.copyWith(
        pendingSeasons: {...data.pendingSeasons, season},
        failedSeasons: {...data.failedSeasons}..remove(season),
      ),
    );
    final detail = data.snapshot.detail;
    final result = await api.updateSeries(
      detail.id,
      detail.editedPayload(seasonMonitored: {season: monitored}),
    );
    if (!ref.mounted || generation != _generation) return;
    final now = _data!;
    final updated = result.valueOrNull;
    if (updated == null) {
      state = AsyncData(
        now.copyWith(
          pendingSeasons: {...now.pendingSeasons}..remove(season),
          failedSeasons: {...now.failedSeasons, season: monitored},
        ),
      );
      return;
    }
    ref
        .read(eventTrackerProvider)
        .track(SeriesMonitorChangedEvent(monitored: monitored));
    state = AsyncData(
      now.copyWith(
        snapshot: now.snapshot.copyWith(detail: updated),
        pendingSeasons: {...now.pendingSeasons}..remove(season),
      ),
    );
    // The server changed the season's episodes too.
    await reloadEpisodes();
  }

  /// Saves the edit sheet's choices (SON-11). Returns the failure, or null.
  Future<AppError?> saveEdit({
    required bool monitored,
    required int? qualityProfileId,
    required List<int> tags,
  }) async {
    final data = _data;
    final api = _api;
    if (data == null || api == null || data.isOffline) {
      return const AppError(ErrorCategory.networkUnreachable);
    }
    final generation = _generation;
    final detail = data.snapshot.detail;
    final result = await api.updateSeries(
      detail.id,
      detail.editedPayload(
        monitored: monitored,
        qualityProfileId: qualityProfileId,
        tags: tags,
      ),
    );
    if (!ref.mounted || generation != _generation) return null;
    final updated = result.valueOrNull;
    if (updated == null) return result.errorOrNull;
    if (updated.summary.monitored != detail.summary.monitored) {
      ref
          .read(eventTrackerProvider)
          .track(
            SeriesMonitorChangedEvent(monitored: updated.summary.monitored),
          );
    }
    final next = _data!.copyWith(
      snapshot: _data!.snapshot.copyWith(detail: updated),
    );
    state = AsyncData(next);
    await _repository?.store(next.snapshot);
    return null;
  }
}

/// Quality profiles and tags: names on the detail screen and choices in the
/// edit sheet. Fails with the [AppError] so the sheet can offer a retry; the
/// detail screen simply omits the names then.
class DetailLookups {
  const DetailLookups({required this.profiles, required this.tags});

  final List<ArrQualityProfile> profiles;
  final List<ArrTag> tags;

  String? profileName(int? id) {
    for (final p in profiles) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  List<String> tagLabels(List<int> ids) => [
    for (final t in tags)
      if (ids.contains(t.id)) t.label,
  ];
}

final detailLookupsProvider = FutureProvider.autoDispose<DetailLookups>(
  retry: (_, _) => null,
  (ref) async {
    final session = await ref.watch(sonarrSessionProvider.future);
    if (session == null) throw const AppError(ErrorCategory.notFound);
    final profiles = await session.api.qualityProfiles();
    final tags = await session.api.tags();
    final error = profiles.errorOrNull ?? tags.errorOrNull;
    if (error != null) throw error;
    return DetailLookups(
      profiles: profiles.valueOrNull!,
      tags: tags.valueOrNull!,
    );
  },
);

/// Creates a tag for the edit sheet (SON-11).
final createTagProvider =
    Provider<Future<Result<ArrTag>> Function(String label)>((ref) {
      return (label) async {
        final session = await ref.read(sonarrSessionProvider.future);
        if (session == null) {
          return const Result.err(AppError(ErrorCategory.notFound));
        }
        return session.api.createTag(label);
      };
    });

/// Artwork of the detail screen: poster and fanart backdrop through the
/// active server's secure client (never another host).
class DetailArtwork {
  DetailArtwork({required this.dio, required SonarrApi api}) : _api = api;

  final Dio dio;
  final SonarrApi _api;

  ImageProvider? poster(SonarrSeries series) =>
      _image(series, ArrImageType.poster);

  ImageProvider? backdrop(SonarrSeries series) =>
      _image(series, ArrImageType.fanart);

  ImageProvider? _image(SonarrSeries series, ArrImageType type) {
    final uri = _api.artworkUri(series, type);
    return uri == null ? null : SecureNetworkImage(dio: dio, uri: uri);
  }
}

/// The artwork source for the detail screen; `null` shows placeholders.
final detailArtworkProvider = Provider.autoDispose<DetailArtwork?>((ref) {
  final session = ref.watch(sonarrSessionProvider).value;
  final dio = session?.dio;
  if (session == null || dio == null) return null;
  return DetailArtwork(dio: dio, api: session.api);
});

/// Opens an external information page in the browser (SON-08).
///
/// A seam: tests override it. Only `https` and `http` URLs are opened, and
/// only when the user taps; nothing is followed automatically.
abstract interface class ExternalLinkLauncher {
  Future<bool> open(Uri uri);
}

/// Whether [uri] may be opened (scheme and host check).
bool isOpenableExternalUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

class UrlLauncherExternalLinkLauncher implements ExternalLinkLauncher {
  const UrlLauncherExternalLinkLauncher();

  @override
  Future<bool> open(Uri uri) async {
    if (!isOpenableExternalUri(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>(
  (ref) => const UrlLauncherExternalLinkLauncher(),
);
