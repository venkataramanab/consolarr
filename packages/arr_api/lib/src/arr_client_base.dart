// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:isolate';

import 'package:arr_api/src/arr_api.dart';
import 'package:arr_api/src/arr_common.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';

/// Runs [computation], possibly on another isolate. Inject an inline version
/// in tests.
typedef ParseRunner = Future<T> Function<T>(T Function() computation);

Future<T> isolateParseRunner<T>(T Function() computation) =>
    Isolate.run(computation);

/// Bodies larger than this are parsed off the UI isolate.
const arrIsolateThresholdBytes = 64 * 1024;

/// Runs [parse] on [body], off the UI isolate when the body is large.
///
/// Top level on purpose: the closure handed to [runner] captures only [body]
/// and [parse]. A closure created inside a client method would drag the whole
/// client (and its unsendable Dio/HttpClient) along and `Isolate.run` would
/// throw. [parse] must itself be a top-level function or a static tear-off.
Future<T> decodeOffIsolate<T>(
  ParseRunner runner,
  String body,
  T Function(String body) parse,
) => body.length > arrIsolateThresholdBytes
    ? runner(() => parse(body))
    : Future.value(parse(body));

/// What Sonarr and Radarr clients share: URL building under a path prefix,
/// the GET helper, artwork URLs and the profile/folder/tag lists (the `v3`
/// APIs of both services are identical there).
///
/// The [Dio] comes from `SecureHttpClientFactory`, already carries auth
/// headers and has `baseUrl` set to the profile's base URI. Paths are
/// relative; the client builds absolute URIs itself so a prefix such as
/// `/sonarr` is always preserved.
abstract class ArrClientBase implements ArrApi {
  ArrClientBase({required this.dio, ParseRunner? parseRunner})
    : runner = parseRunner ?? isolateParseRunner;

  /// Bodies larger than this are parsed off the UI isolate.
  static const isolateThresholdBytes = arrIsolateThresholdBytes;

  /// Oldest supported major version (Sonarr and Radarr v3).
  static const minMajorVersion = 3;

  final Dio dio;
  final ParseRunner runner;

  Uri get base => Uri.parse(dio.options.baseUrl);

  Uri uri(String relativePath) {
    final b = base;
    final prefix = [...b.pathSegments.where((s) => s.isNotEmpty)];
    return b.replace(
      pathSegments: [...prefix, ...relativePath.split('/')],
      query: null,
    );
  }

  Future<String> getText(String path) async {
    final response = await dio.getUri<String>(
      uri(path),
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  /// Runs [body], mapping every failure to a typed [AppError].
  Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Result.ok(await body());
    } on FormatException {
      return const Result.err(AppError(ErrorCategory.parseError));
    } on Object catch (e) {
      return Result.err(appErrorFromDio(e));
    }
  }

  Future<Result<List<T>>> _list<T>(
    String path,
    T Function(Map<String, Object?> json) parse,
  ) => guard(() async {
    final parsed = parseArrList(jsonDecode(await getText(path)), parse);
    return parsed.items;
  });

  @override
  Future<Result<List<ArrQualityProfile>>> qualityProfiles() =>
      _list('api/v3/qualityprofile', ArrQualityProfile.fromJson);

  @override
  Future<Result<List<ArrRootFolder>>> rootFolders() =>
      _list('api/v3/rootfolder', ArrRootFolder.fromJson);

  @override
  Future<Result<List<ArrTag>>> tags() => _list('api/v3/tag', ArrTag.fromJson);

  /// The server-relative artwork URL of the first [images] entry of [type].
  /// Never contains credentials and never points at another host.
  Uri? artworkUriFor(List<ArrImage> images, ArrImageType type) {
    for (final image in images) {
      if (image.type != type) continue;
      final raw = image.url;
      if (raw == null || raw.isEmpty) continue;
      final parsed = Uri.tryParse(raw);
      // Only server-relative paths: never an absolute (third-party) URL.
      if (parsed == null || parsed.hasScheme || parsed.hasAuthority) continue;
      if (!parsed.path.startsWith('/')) continue;

      final b = base;
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
