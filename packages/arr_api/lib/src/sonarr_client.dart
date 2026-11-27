// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:isolate';

import 'package:arr_api/src/arr_api.dart';
import 'package:arr_api/src/models.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';

/// Runs [computation], possibly on another isolate. Inject an inline version
/// in tests.
typedef ParseRunner = Future<T> Function<T>(T Function() computation);

Future<T> _isolateRunner<T>(T Function() computation) =>
    Isolate.run(computation);

List<SonarrSeries> _parseSeries(String body) => parseSeriesList(body);

/// Hand-written, tolerant Sonarr v3 client (also works with v4).
///
/// The [Dio] comes from `SecureHttpClientFactory`, already carries auth
/// headers and has `baseUrl` set to the profile's base URI (scheme, host,
/// port and optional path prefix). Paths here are relative; the client builds
/// absolute URIs itself so a prefix such as `/sonarr` is always preserved.
class SonarrClient implements SonarrApi {
  SonarrClient({required Dio dio, ParseRunner? parseRunner})
    : _dio = dio,
      _runner = parseRunner ?? _isolateRunner;

  /// Bodies larger than this are parsed off the UI isolate.
  static const isolateThresholdBytes = 64 * 1024;

  /// Oldest supported major version (Sonarr v3).
  static const minMajorVersion = 3;

  final Dio _dio;
  final ParseRunner _runner;

  @override
  ServiceKind get kind => ServiceKind.sonarr;

  Uri get _base => Uri.parse(_dio.options.baseUrl);

  Uri _uri(String relativePath) {
    final b = _base;
    final prefix = [...b.pathSegments.where((s) => s.isNotEmpty)];
    return b.replace(
      pathSegments: [...prefix, ...relativePath.split('/')],
      query: null,
    );
  }

  Future<String> _get(String path) async {
    final response = await _dio.getUri<String>(
      _uri(path),
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  @override
  Future<Result<ArrSystemStatus>> systemStatus() async {
    try {
      final ArrSystemStatus status;
      try {
        status = parseSystemStatus(await _get('api/v3/system/status'));
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        return await _probeLegacy();
      }
      return _checkVersion(status);
    } on FormatException {
      return const Result.err(AppError(ErrorCategory.parseError));
    } on Object catch (e) {
      return Result.err(appErrorFromDio(e));
    }
  }

  /// Sonarr v2 only has `api/system/status`.
  Future<Result<ArrSystemStatus>> _probeLegacy() async {
    try {
      final legacy = parseSystemStatus(await _get('api/system/status'));
      final major = legacy.majorVersion;
      if (major != null && major < minMajorVersion) {
        return const Result.err(AppError(ErrorCategory.unsupportedVersion));
      }
    } on Object {
      // Fall through: the probe is best effort.
    }
    return const Result.err(AppError(ErrorCategory.notFound));
  }

  Result<ArrSystemStatus> _checkVersion(ArrSystemStatus status) {
    final major = status.majorVersion;
    if (major != null && major < minMajorVersion) {
      return const Result.err(AppError(ErrorCategory.unsupportedVersion));
    }
    return Result.ok(status);
  }

  @override
  Future<Result<List<SonarrSeries>>> series() async {
    try {
      final body = await _get('api/v3/series');
      final list = body.length > isolateThresholdBytes
          ? await _runner(() => _parseSeries(body))
          : parseSeriesList(body);
      return Result.ok(list);
    } on FormatException {
      return const Result.err(AppError(ErrorCategory.parseError));
    } on Object catch (e) {
      return Result.err(appErrorFromDio(e));
    }
  }

  @override
  Uri? artworkUri(SonarrSeries series, SonarrImageType type) {
    for (final image in series.images) {
      if (image.type != type) continue;
      final raw = image.url;
      if (raw == null || raw.isEmpty) continue;
      final parsed = Uri.tryParse(raw);
      // Only server-relative paths: never an absolute (third-party) URL.
      if (parsed == null || parsed.hasScheme || parsed.hasAuthority) continue;
      if (!parsed.path.startsWith('/')) continue;

      final b = _base;
      final prefix = b.path.endsWith('/')
          ? b.path.substring(0, b.path.length - 1)
          : b.path;
      final path =
          prefix.isNotEmpty &&
              (parsed.path == prefix || parsed.path.startsWith('$prefix/'))
          ? parsed.path
          : '$prefix${parsed.path}';
      final query = {
        for (final e in parsed.queryParameters.entries)
          if (!_isSecretParam(e.key)) e.key: e.value,
      };
      return b.replace(
        path: path,
        queryParameters: query.isEmpty ? null : query,
      );
    }
    return null;
  }

  static bool _isSecretParam(String name) {
    final n = name.toLowerCase().replaceAll(RegExp('[-_]'), '');
    return n.contains('key') || n.contains('token') || n.contains('auth');
  }
}
