// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/src/arr_api.dart';
import 'package:arr_api/src/arr_client_base.dart';
import 'package:arr_api/src/models.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';

ParsedRows<SonarrSeries> _parseSeries(String body) => parseSeriesList(body);

/// Hand-written, tolerant Sonarr v3 client (also works with v4).
///
/// URL building, artwork URLs and the shared lists (quality profiles, root
/// folders, tags) come from [ArrClientBase].
class SonarrClient extends ArrClientBase implements SonarrApi {
  SonarrClient({required super.dio, super.parseRunner, this.onRowsSkipped});

  /// Called with the number of malformed series rows that were skipped (only
  /// when greater than zero). A count only: never row content.
  final void Function(int skipped)? onRowsSkipped;

  @override
  ServiceKind get kind => ServiceKind.sonarr;

  @override
  Future<Result<ArrSystemStatus>> systemStatus() async {
    try {
      final ArrSystemStatus status;
      try {
        status = parseSystemStatus(await getText('api/v3/system/status'));
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
      final legacy = parseSystemStatus(await getText('api/system/status'));
      final major = legacy.majorVersion;
      if (major != null && major < ArrClientBase.minMajorVersion) {
        return const Result.err(AppError(ErrorCategory.unsupportedVersion));
      }
    } on Object {
      // Fall through: the probe is best effort.
    }
    return const Result.err(AppError(ErrorCategory.notFound));
  }

  Result<ArrSystemStatus> _checkVersion(ArrSystemStatus status) {
    final major = status.majorVersion;
    if (major != null && major < ArrClientBase.minMajorVersion) {
      return const Result.err(AppError(ErrorCategory.unsupportedVersion));
    }
    return Result.ok(status);
  }

  @override
  Future<Result<List<SonarrSeries>>> series() => guard(() async {
    final body = await getText('api/v3/series');
    final parsed = body.length > ArrClientBase.isolateThresholdBytes
        ? await runner(() => _parseSeries(body))
        : parseSeriesList(body);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Uri? artworkUri(SonarrSeries series, SonarrImageType type) =>
      artworkUriFor(series.images, type);
}
