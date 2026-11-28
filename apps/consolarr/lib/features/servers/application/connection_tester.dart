// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/servers/application/auth_headers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:consolarr/shared/logging/log_events.dart';
import 'package:consolarr/shared/logging/logging_interceptor.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// The lightweight status/version query for one service kind: builds the
/// client on the already configured [dio] and reads the version.
typedef ConnectionProbe = Future<ConnectionTestOutcome> Function(
  Dio dio,
  ServerProfile profile,
  ServerCredentials credentials,
);

Future<ConnectionTestOutcome> _probeSonarr(
  Dio dio,
  ServerProfile profile,
  ServerCredentials credentials,
) async => _fromResult(
  (await SonarrClient(
    dio: dio,
  ).systemStatus()).map((s) => (s.version, s.majorVersion)),
);

Future<ConnectionTestOutcome> _probeRadarr(
  Dio dio,
  ServerProfile profile,
  ServerCredentials credentials,
) async => _fromResult(
  (await RadarrClient(
    dio: dio,
  ).systemStatus()).map((s) => (s.version, s.majorVersion)),
);

Future<ConnectionTestOutcome> _probeQBittorrent(
  Dio dio,
  ServerProfile profile,
  ServerCredentials credentials,
) async => _fromResult(
  (await QBittorrentClient(
    dio: dio,
    username: credentials.username,
    password: credentials.password,
  ).fetchVersion()).map((v) => (v, _major(v))),
);

Future<ConnectionTestOutcome> _probeTransmission(
  Dio dio,
  ServerProfile profile,
  ServerCredentials credentials,
) async => _fromResult(
  (await TransmissionClient(
    dio: dio,
    username: credentials.username,
    password: credentials.password,
  ).fetchVersion()).map((v) => (v, _major(v))),
);

Future<ConnectionTestOutcome> _probeDeluge(
  Dio dio,
  ServerProfile profile,
  ServerCredentials credentials,
) async => _fromResult(
  (await DelugeClient(
    dio: dio,
    password: credentials.password,
  ).fetchVersion()).map((v) => (v, _major(v))),
);

/// Connection probes per service kind. A new service registers its probe here
/// (and in `supportedServiceKinds`); there is deliberately no catch-all, so a
/// kind is never reported as something it is not.
final Map<ServiceKind, ConnectionProbe> connectionProbes = {
  ServiceKind.sonarr: _probeSonarr,
  ServiceKind.radarr: _probeRadarr,
  ServiceKind.qbittorrent: _probeQBittorrent,
  ServiceKind.transmission: _probeTransmission,
  ServiceKind.deluge: _probeDeluge,
};

/// The outcome for a kind that has no probe registered. It is not reachable
/// from the UI (pickers list the registered kinds); it is explicit, and not
/// `unsupported_version`, so it can never be mistaken for an old server.
const _noProbe = ConnectionTestFailure(
  AppError(
    ErrorCategory.parseError,
    debugDetail: 'no connection probe registered for this service kind',
  ),
);

/// Runs the lightweight status/version query through the secure client
/// (SRV-05, SRV-10). Typed TLS errors are passed through unchanged so the UI
/// can answer with the trust sheet.
///
/// With a [logger] each test attaches the request logger (route and status
/// only) and ends with `connection_test kind=<kind> result=<category|ok>`.
class DefaultConnectionTester implements ConnectionTester {
  DefaultConnectionTester(
    this._factory, {
    Map<ServiceKind, ConnectionProbe>? probes,
    AppLogger? logger,
  }) : _probes = probes ?? connectionProbes,
       _logger = logger;

  final SecureHttpClientFactory _factory;
  final Map<ServiceKind, ConnectionProbe> _probes;
  final AppLogger? _logger;

  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials credentials,
  ) async {
    final probe = _probes[profile.kind];
    if (probe == null) return _noProbe;
    final dio = _factory.create(profile);
    dio.options.headers.addAll(buildAuthHeaders(profile, credentials));
    final logger = _logger;
    if (logger != null) {
      dio.interceptors.add(
        LoggingInterceptor(logger, pathPrefix: profile.pathPrefix),
      );
    }
    ConnectionTestOutcome outcome;
    try {
      outcome = await probe(dio, profile, credentials);
    } on Object catch (e) {
      outcome = ConnectionTestFailure(appErrorFromDio(e));
    } finally {
      dio.close(force: true);
    }
    if (logger != null) {
      logConnectionTest(
        logger,
        profile.kind,
        outcome is ConnectionTestFailure ? outcome.error : null,
      );
    }
    return outcome;
  }
}

ConnectionTestOutcome _fromResult(Result<(String, int?)> r) => r.when(
  ok: (v) => ConnectionTestSuccess(version: v.$1, majorVersion: v.$2),
  err: ConnectionTestFailure.new,
);

/// `v4.6.3` / `5.0.0` -> 4 / 5.
int? _major(String version) =>
    int.tryParse(RegExp(r'\d+').firstMatch(version)?.group(0) ?? '');

/// Reports `connection_test_result` (closed enums only) for each test.
class TrackedConnectionTester implements ConnectionTester {
  TrackedConnectionTester(this._inner, this._tracker);

  final ConnectionTester _inner;
  final EventTracker _tracker;

  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials credentials,
  ) async {
    final outcome = await _inner.test(profile, credentials);
    final kind = ServiceKindParam.fromCode(profile.kind.name);
    if (kind != null) {
      await _tracker.track(switch (outcome) {
        ConnectionTestSuccess(:final majorVersion) => ConnectionTestResultEvent(
          serviceKind: kind,
          majorVersion: majorVersion,
        ),
        ConnectionTestFailure(:final error) => ConnectionTestResultEvent(
          serviceKind: kind,
          errorCategory: ErrorCategoryParam.fromCode(error.category.code),
        ),
      });
    }
    return outcome;
  }
}
