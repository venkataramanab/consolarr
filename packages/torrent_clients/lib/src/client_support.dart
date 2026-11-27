// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:security/security.dart';

/// Runs [body] and turns every failure into a typed [AppError] (no exception
/// leaves a client). A [FormatException] is a `parse_error`.
Future<Result<T>> guardResult<T>(Future<T> Function() body) async {
  try {
    return Result.ok(await body());
  } on FormatException {
    return const Result.err(AppError(ErrorCategory.parseError));
  } on TypeError {
    return const Result.err(AppError(ErrorCategory.parseError));
  } on Object catch (e) {
    return Result.err(appErrorFromDio(e));
  }
}

/// `base` plus [relativePath] segments (keeps a reverse-proxy path prefix),
/// without any query.
Uri joinUri(Uri base, String relativePath) => base.replace(
  pathSegments: [
    ...base.pathSegments.where((s) => s.isNotEmpty),
    ...relativePath.split('/'),
  ],
  query: null,
);

/// Parses the leading `major.minor` of a version string.
(int, int)? parseMajorMinor(String version) {
  final m = RegExp(r'(\d+)\.(\d+)').firstMatch(version);
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!));
}
