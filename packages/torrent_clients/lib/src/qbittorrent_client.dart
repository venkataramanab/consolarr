// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:isolate';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:torrent_clients/src/models.dart';
import 'package:torrent_clients/src/torrent_client.dart';

/// Runs [computation], possibly on another isolate. Inject an inline version
/// in tests.
typedef ParseRunner = Future<T> Function<T>(T Function() computation);

Future<T> _isolateRunner<T>(T Function() computation) =>
    Isolate.run(computation);

List<Torrent> _parseTorrents(String body) => parseTorrentList(body);

/// qBittorrent WebUI API v2 client (cookie login).
///
/// The [Dio] comes from `SecureHttpClientFactory` with `baseUrl` set to the
/// profile's base URI. The session cookie lives in this object's memory only:
/// it is never persisted, logged or placed in an error. Without a username and
/// password no login is attempted (servers that bypass authentication).
///
/// WebUI API v2 exists since qBittorrent 4.1; older servers fail with
/// `unsupported_version`.
class QBittorrentClient implements TorrentClient {
  QBittorrentClient({
    required Dio dio,
    String? username,
    String? password,
    ParseRunner? parseRunner,
  }) : _dio = dio,
       _username = username,
       _password = password,
       _runner = parseRunner ?? _isolateRunner;

  /// Bodies larger than this are parsed off the UI isolate.
  static const isolateThresholdBytes = 64 * 1024;

  final Dio _dio;
  final String? _username;
  final String? _password;
  final ParseRunner _runner;

  String? _cookie;

  bool get _hasCredentials =>
      (_username?.isNotEmpty ?? false) && (_password?.isNotEmpty ?? false);

  @override
  ServiceKind get kind => ServiceKind.qbittorrent;

  /// Forgets the in-memory session (for example after credentials change).
  void forgetSession() => _cookie = null;

  Uri get _base => Uri.parse(_dio.options.baseUrl);

  Uri _uri(String relativePath) => _base.replace(
    pathSegments: [
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      ...relativePath.split('/'),
    ],
    query: null,
  );

  Map<String, String> get _csrfHeaders {
    final b = _base;
    final origin = Uri(
      scheme: b.scheme,
      host: b.host,
      port: b.hasPort ? b.port : null,
    );
    return {
      'Referer': _dio.options.baseUrl,
      'Origin': origin.toString(),
      if (_cookie != null) 'Cookie': _cookie!,
    };
  }

  /// Logs in; throws [AppError] on failure.
  Future<void> _login() async {
    final Response<String> response;
    try {
      response = await _dio.postUri<String>(
        _uri('api/v2/auth/login'),
        data:
            'username=${Uri.encodeQueryComponent(_username!)}'
            '&password=${Uri.encodeQueryComponent(_password!)}',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: _csrfHeaders..remove('Cookie'),
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw const AppError(ErrorCategory.authFailed, debugDetail: 'banned');
      }
      throw appErrorFromDio(e);
    }
    if ((response.data ?? '').trim() != 'Ok.') {
      throw const AppError(ErrorCategory.authFailed);
    }
    final setCookies = response.headers['set-cookie'] ?? const [];
    final pairs = [
      for (final c in setCookies)
        if (c.split(';').first.contains('=')) c.split(';').first.trim(),
    ];
    _cookie = pairs.isEmpty ? null : pairs.join('; ');
  }

  Future<String> _get(String path, {bool retry = true}) async {
    if (_hasCredentials && _cookie == null) await _login();
    try {
      final response = await _dio.getUri<String>(
        _uri(path),
        options: Options(
          responseType: ResponseType.plain,
          headers: _csrfHeaders,
        ),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (retry && _hasCredentials && (status == 403 || status == 401)) {
        _cookie = null;
        return _get(path, retry: false);
      }
      rethrow;
    }
  }

  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Result.ok(await body());
    } on FormatException {
      return const Result.err(AppError(ErrorCategory.parseError));
    } on Object catch (e) {
      return Result.err(appErrorFromDio(e));
    }
  }

  @override
  Future<Result<String>> fetchVersion() => _guard(() async {
    final version = (await _get('api/v2/app/version')).trim();
    final m = RegExp(r'^v?(\d+)\.(\d+)').firstMatch(version);
    if (m != null) {
      final major = int.parse(m[1]!);
      final minor = int.parse(m[2]!);
      if (major < 4 || (major == 4 && minor < 1)) {
        throw const AppError(ErrorCategory.unsupportedVersion);
      }
    }
    return version;
  });

  @override
  Future<Result<List<Torrent>>> listTorrents() => _guard(() async {
    final body = await _get('api/v2/torrents/info');
    return body.length > isolateThresholdBytes
        ? await _runner(() => _parseTorrents(body))
        : parseTorrentList(body);
  });

  @override
  Future<Result<TransferInfo>> transferInfo() =>
      _guard(() async => parseTransferInfo(await _get('api/v2/transfer/info')));
}
