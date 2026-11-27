// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/servers/application/auth_headers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/domain/server_repository.dart';
import 'package:core/core.dart';
import 'package:observability/observability.dart';
import 'package:security/security.dart';
import 'package:torrent_clients/torrent_clients.dart';

/// Runs the lightweight status/version query through the secure client
/// (SRV-05, SRV-10). Typed TLS errors are passed through unchanged so the UI
/// can answer with the trust sheet.
class DefaultConnectionTester implements ConnectionTester {
  DefaultConnectionTester(this._factory);

  final SecureHttpClientFactory _factory;

  @override
  Future<ConnectionTestOutcome> test(
    ServerProfile profile,
    ServerCredentials credentials,
  ) async {
    final dio = _factory.create(profile);
    dio.options.headers.addAll(buildAuthHeaders(profile, credentials));
    try {
      return switch (profile.kind) {
        ServiceKind.sonarr => _fromResult(
          (await SonarrClient(
            dio: dio,
          ).systemStatus()).map((s) => (s.version, s.majorVersion)),
        ),
        ServiceKind.qbittorrent => _fromResult(
          (await QBittorrentClient(
            dio: dio,
            username: credentials.username,
            password: credentials.password,
          ).fetchVersion()).map((v) => (v, _major(v))),
        ),
        _ => const ConnectionTestFailure(
          AppError(
            ErrorCategory.unsupportedVersion,
            debugDetail: 'service not supported yet',
          ),
        ),
      };
    } on Object catch (e) {
      return ConnectionTestFailure(appErrorFromDio(e));
    } finally {
      dio.close(force: true);
    }
  }

  static ConnectionTestOutcome _fromResult(Result<(String, int?)> r) => r.when(
    ok: (v) => ConnectionTestSuccess(version: v.$1, majorVersion: v.$2),
    err: ConnectionTestFailure.new,
  );

  /// `v4.6.3` / `5.0.0` -> 4 / 5.
  static int? _major(String version) =>
      int.tryParse(RegExp(r'\d+').firstMatch(version)?.group(0) ?? '');
}

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
