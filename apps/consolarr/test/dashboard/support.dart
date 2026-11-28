// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:consolarr/features/dashboard/application/dashboard_models.dart';
import 'package:consolarr/features/dashboard/application/dashboard_providers.dart';
import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/data/dashboard_cache.dart';
import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/first_frame.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:observability/observability.dart';

/// "Now" of every dashboard test: 2026-03-10 12:00 UTC.
final fixedNow = DateTime.utc(2026, 3, 10, 12);

// --- fake servers ---------------------------------------------------------------

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions options);

ResponseBody jsonBody(Object body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// A fake server: answers by the end of the request path, counts requests and
/// how many are in flight at once, and can be held back with [gate].
///
/// Like the real adapter it cannot be sent to another isolate (it owns a
/// [ReceivePort]), so a parse closure that captures the client fails here as
/// it would on a device.
class FakeServer implements HttpClientAdapter {
  FakeServer([Map<String, Handler>? routes]) : routes = routes ?? {};

  final Map<String, Handler> routes;
  final List<RequestOptions> requests = [];
  final ReceivePort _port = ReceivePort();
  Completer<void>? gate;
  Duration? delay;
  int inFlight = 0;
  int maxInFlight = 0;

  /// Requests that were cancelled by the client.
  int cancelledRequests = 0;

  /// Requests per path suffix.
  int count(String suffix) =>
      requests.where((r) => r.uri.path.endsWith(suffix)).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    // Like a real adapter, a cancelled request ends at once.
    final cancelled = Completer<Never>();
    unawaited(
      cancelFuture?.then((_) {
        cancelledRequests++;
        if (!cancelled.isCompleted) {
          cancelled.completeError(
            DioException.requestCancelled(
              requestOptions: options,
              reason: 'cancelled',
            ),
          );
        }
      }),
    );
    Future<ResponseBody> serve() async {
      if (gate != null) await gate!.future;
      if (delay != null) await Future<void>.delayed(delay!);
      for (final e in routes.entries) {
        if (options.uri.path.endsWith(e.key)) return await e.value(options);
      }
      return ResponseBody.fromString('not found', 404);
    }

    try {
      return await Future.any([serve(), cancelled.future]);
    } finally {
      inFlight--;
    }
  }

  @override
  void close({bool force = false}) => _port.close();
}

ServerConnection connection(
  ServiceKind kind,
  String id,
  FakeServer server, {
  String? name,
}) {
  final profile = ServerProfile.parse(
    id: id,
    name: name ?? 'Server $id',
    kind: kind,
    address: 'https://$id.example',
  ).valueOrNull!;
  final dio = Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
    ..httpClientAdapter = server;
  return ServerConnection(profile: profile, dio: dio);
}

// --- fake payloads ----------------------------------------------------------------

Map<String, Object?> seriesJson(int id, String title) => {
  'id': id,
  'title': title,
  'sortTitle': title.toLowerCase(),
  'images': [
    {'coverType': 'poster', 'url': '/MediaCover/$id/poster.jpg?lastWrite=1'},
  ],
};

Map<String, Object?> episodeJson({
  required int id,
  required int seriesId,
  String series = 'Example Show',
  int season = 2,
  int episode = 5,
  String? airDateUtc,
  String? airDate,
}) => {
  'id': id,
  'seriesId': seriesId,
  'seasonNumber': season,
  'episodeNumber': episode,
  'title': 'Example Episode',
  'airDateUtc': ?airDateUtc,
  'airDate': ?airDate,
  'series': seriesJson(seriesId, series),
};

Map<String, Object?> movieJson({
  required int id,
  String title = 'Example Movie',
  String? inCinemas,
  String? digitalRelease,
  String? physicalRelease,
}) => {
  'id': id,
  'title': title,
  'sortTitle': title.toLowerCase(),
  'inCinemas': ?inCinemas,
  'digitalRelease': ?digitalRelease,
  'physicalRelease': ?physicalRelease,
  'images': [
    {'coverType': 'poster', 'url': '/MediaCover/$id/poster.jpg'},
  ],
};

Map<String, Object?> queueJson({
  required int id,
  String title = 'Example.Release.1080p',
  String status = 'downloading',
  int size = 1000,
  int left = 400,
  String? series,
  int? seriesId,
  int? movieId,
  String? tdStatus,
  String? tdState,
}) => {
  'id': id,
  'title': title,
  'status': status,
  'size': size,
  'sizeleft': left,
  'seriesId': ?seriesId,
  'movieId': ?movieId,
  'trackedDownloadStatus': ?tdStatus,
  'trackedDownloadState': ?tdState,
  if (series != null) 'series': {'title': series},
};

Object page(List<Object?> records, {int pageSize = 200}) => {
  'page': 1,
  'pageSize': pageSize,
  'totalRecords': records.length,
  'records': records,
};

Map<String, Object?> historyRowJson({
  required int id,
  int? seriesId,
  int? movieId,
  String title = 'Example Show',
  String date = '2026-03-10T10:00:00Z',
}) => {
  'id': id,
  'seriesId': ?seriesId,
  'movieId': ?movieId,
  'eventType': 'downloadFolderImported',
  'date': date,
  if (seriesId != null) ...{
    'series': seriesJson(seriesId, title),
    'episode': {'seasonNumber': 1, 'episodeNumber': id, 'title': 'Pilot'},
  },
  if (movieId != null) 'movie': movieJson(id: movieId, title: title),
};

// --- providers --------------------------------------------------------------------

class _FirstFrameDone extends FirstFrameDone {
  @override
  bool build() => true;
}

/// What each kind's active connection is: a [ServerConnection], `null` (none
/// configured), an [AppError] (the connection fails) or a [Completer] that has
/// not completed yet (still resolving).
class ActiveConnections extends Notifier<Map<ServiceKind, Object?>> {
  @override
  Map<ServiceKind, Object?> build() => const {};

  void set(ServiceKind kind, Object? value) => state = {...state, kind: value};
}

final activeConnections =
    NotifierProvider<ActiveConnections, Map<ServiceKind, Object?>>(
      ActiveConnections.new,
    );

class MemoryPayloadCache implements PayloadCache {
  final Map<(String, String), CachedPayload> rows = {};

  @override
  Future<CachedPayload?> read(String serverId, String key) async =>
      rows[(serverId, key)];

  @override
  Future<void> write(
    String serverId,
    String key,
    String json,
    DateTime fetchedAt,
  ) async =>
      rows[(serverId, key)] = CachedPayload(json: json, fetchedAt: fetchedAt);

  @override
  Future<void> deleteForServer(String serverId) async =>
      rows.removeWhere((k, _) => k.$1 == serverId);

  @override
  Future<void> delete(String serverId, String key) async =>
      rows.remove((serverId, key));

  @override
  Future<void> pruneKeys(String keyPrefix, Set<String> keepServerIds) async =>
      rows.removeWhere(
        (k, _) => k.$2.startsWith(keyPrefix) && !keepServerIds.contains(k.$1),
      );
}

class RecordingAnalytics implements Analytics {
  final List<({String name, Map<String, Object> parameters})> events = [];

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async => events.add((name: name, parameters: parameters));
}

/// Everything a dashboard test needs besides the servers.
class Env {
  Env({
    Map<ServiceKind, DashboardSource>? sources,
    this.deadline = const Duration(seconds: 20),
    this.now,
  }) : sources = sources ?? const {};

  final Map<ServiceKind, DashboardSource> sources;
  final Duration deadline;
  final DateTime Function()? now;
  final analytics = RecordingAnalytics();
  final breadcrumbs = Breadcrumbs();
  final cache = MemoryPayloadCache();
  final List<String> logs = [];

  /// The stored servers: `null` (unknown) means nothing is ever pruned.
  Set<String>? serverIds;
  late Future<Set<String>?> Function() serverIdsLoader = () async => serverIds;

  /// Reads the credentials of a profile; counts its calls.
  final List<String> credentialReads = [];
  Future<ServerCredentials> credentialLoader(ServerProfile profile) async {
    credentialReads.add(profile.id);
    return const ServerCredentials();
  }

  late final DashboardCache dashboardCache = DashboardCache(cache);

  /// [realConnections] keeps the app's own `activeConnectionProvider` (the
  /// caller overrides the repository and the HTTP client factory instead).
  List<Override> overrides({
    bool firstFrameDone = true,
    Map<ServiceKind, DashboardSource>? sources,
    bool realConnections = false,
  }) => [
    if (firstFrameDone)
      firstFrameDoneProvider.overrideWith(_FirstFrameDone.new),
    dashboardSourcesProvider.overrideWithValue(sources ?? this.sources),
    dashboardDeadlineProvider.overrideWithValue(deadline),
    dashboardCacheProvider.overrideWithValue(dashboardCache),
    dashboardCredentialLoaderProvider.overrideWithValue(
      (profile) async => credentialLoader(profile),
    ),
    dashboardServerIdsProvider.overrideWithValue(() => serverIdsLoader()),
    clockProvider.overrideWithValue(now ?? () => fixedNow),
    eventTrackerProvider.overrideWithValue(
      EventTracker(analytics: analytics, breadcrumbs: breadcrumbs),
    ),
    breadcrumbsProvider.overrideWithValue(breadcrumbs),
    loggerProvider.overrideWithValue(
      AppLogger(sink: (level, message) => logs.add(message)),
    ),
    if (!realConnections)
      activeConnectionProvider.overrideWith((ref, kind) async {
        final value = ref.watch(
          activeConnections.select((m) => m.containsKey(kind) ? m[kind] : null),
        );
        if (value is Completer<ServerConnection?>) return value.future;
        if (value is AppError) throw value;
        return value as ServerConnection?;
      }),
    if (!realConnections)
      activeConnectionKeyProvider.overrideWith(
        (ref, kind) => Stream.value(ConnectionKey('failed-${kind.name}', 1)),
      ),
    if (!realConnections)
      serversProvider.overrideWith(
        (ref) => Stream.value([
          for (final kind in ServiceKind.values)
            ServerEntry(
              profile: ServerProfile.parse(
                id: 'failed-${kind.name}',
                name: 'Server one',
                kind: kind,
                address: 'https://failed.example',
              ).valueOrNull!,
              sortOrder: 0,
            ),
        ]),
      ),
  ];

  ProviderContainer container({
    bool firstFrameDone = true,
    Map<ServiceKind, DashboardSource>? sources,
    List<Override> extra = const [],
    bool realConnections = false,
  }) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...overrides(
          firstFrameDone: firstFrameDone,
          sources: sources,
          realConnections: realConnections,
        ),
        ...extra,
      ],
    );
    addTearDownContainer(c);
    return c;
  }
}

final List<ProviderContainer> _containers = [];

void addTearDownContainer(ProviderContainer c) => _containers.add(c);

void disposeContainers() {
  for (final c in _containers) {
    c.dispose();
  }
  _containers.clear();
}

/// A source whose fetches run [onFetch] and are counted.
class CountingSource {
  CountingSource({
    this.activity = const Result.ok(
      ActivitySummary(
        active: 1,
        attention: 0,
        rows: [],
        link: DashboardLink(
          '/sonarr',
          DashboardTarget.tab,
          DashboardDestination.sonarr,
        ),
      ),
    ),
    this.upcoming = const Result.ok([]),
    this.recent = const Result.ok([]),
    this.feedsMedia = true,
  });

  Result<ActivitySummary> activity;
  Result<List<MediaItem>> upcoming;
  Result<List<MediaItem>> recent;
  final bool feedsMedia;

  final Map<DashboardCard, int> calls = {
    for (final c in DashboardCard.values) c: 0,
  };
  final Map<DashboardCard, Completer<void>?> gates = {};
  int inFlight = 0;
  int maxInFlight = 0;

  Future<T> _run<T>(DashboardCard card, T value) async {
    calls[card] = calls[card]! + 1;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final gate = gates[card];
      if (gate != null) await gate.future;
      return value;
    } finally {
      inFlight--;
    }
  }

  DashboardSource get source => DashboardSource(
    activity: (c) => _run(DashboardCard.activity, activity),
    upcoming: feedsMedia ? (c) => _run(DashboardCard.upcoming, upcoming) : null,
    recent: feedsMedia ? (c) => _run(DashboardCard.recent, recent) : null,
  );
}

MediaItem mediaItem(
  String id, {
  String title = 'Example Show',
  required ServerConnection from,
  DateTime? day,
  DateTime? at,
  int? season,
  int? episode,
  MovieRelease release = MovieRelease.none,
}) => MediaItem(
  id: id,
  title: title,
  link: const DashboardLink(
    '/sonarr/series/1',
    DashboardTarget.detail,
    DashboardDestination.series,
  ),
  dio: from.dio,
  day: day,
  at: at,
  season: season,
  episode: episode,
  release: release,
);
