// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:torrent_clients/src/client_support.dart';
import 'package:torrent_clients/src/models.dart';
import 'package:torrent_clients/src/parse_runner.dart';
import 'package:torrent_clients/src/torrent_actions.dart';
import 'package:torrent_clients/src/torrent_capabilities.dart';
import 'package:torrent_clients/src/torrent_client.dart';

ParsedRows<Torrent> _parseTorrents(String body) => parseTorrentList(body);

/// Top level on purpose: the closure given to [runner] captures only [body],
/// never the client (its Dio/HttpClient cannot be sent to another isolate).
Future<ParsedRows<Torrent>> _parseOffIsolate(ParseRunner runner, String body) =>
    body.length > isolateThresholdBytes
    ? runner(() => _parseTorrents(body))
    : Future.value(_parseTorrents(body));

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
    this.onRowsSkipped,
  }) : _dio = dio,
       _username = username,
       _password = password,
       _runner = parseRunner ?? isolateRunner;

  /// Called with the number of malformed torrent rows that were skipped (only
  /// when greater than zero). A count only: never row content.
  final void Function(int skipped)? onRowsSkipped;

  final Dio _dio;
  final String? _username;
  final String? _password;
  final ParseRunner _runner;

  String? _cookie;

  /// Detected from `app/version`; `null` until known.
  int? _major;

  bool get _hasCredentials =>
      (_username?.isNotEmpty ?? false) && (_password?.isNotEmpty ?? false);

  @override
  ServiceKind get kind => ServiceKind.qbittorrent;

  @override
  TorrentCapabilities get capabilities => TorrentCapabilities(
    alternativeSpeed: true,
    labelModel: LabelModel.category,
    tags: true,
    distinctStop: (_major ?? 0) >= 5,
  );

  @override
  void forgetSession() {
    _cookie = null;
    _major = null;
  }

  Uri get _base => Uri.parse(_dio.options.baseUrl);

  Uri _uri(String relativePath) => joinUri(_base, relativePath);

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

  Future<String> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? data,
    String? contentType,
    bool retry = true,
  }) async {
    if (_hasCredentials && _cookie == null) await _login();
    try {
      final uri = query == null
          ? _uri(path)
          : _uri(path).replace(
              queryParameters: {
                for (final e in query.entries) e.key: '${e.value}',
              },
            );
      final response = await _dio.requestUri<String>(
        uri,
        data: data,
        options: Options(
          method: method,
          contentType: contentType,
          responseType: ResponseType.plain,
          headers: _csrfHeaders,
        ),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (retry && _hasCredentials && (status == 403 || status == 401)) {
        _cookie = null;
        return _send(
          method,
          path,
          query: query,
          data: data is FormData ? data.clone() : data,
          contentType: contentType,
          retry: false,
        );
      }
      rethrow;
    }
  }

  Future<String> _get(String path, {Map<String, Object?>? query}) =>
      _send('GET', path, query: query);

  Future<String> _postForm(String path, Map<String, String> form) => _send(
    'POST',
    path,
    data: form.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&'),
    contentType: Headers.formUrlEncodedContentType,
  );

  Future<Result<T>> _guard<T>(Future<T> Function() body) => guardResult(body);

  /// The major version, detected once and cached.
  Future<int> _detectMajor() async {
    final known = _major;
    if (known != null) return known;
    final version = (await _get('api/v2/app/version')).trim();
    return _major = parseMajorMinor(version)?.$1 ?? 4;
  }

  /// Runs the v5 name first on v5+ servers (`stop`/`start`) and the v4 name
  /// (`pause`/`resume`) otherwise; a 404 falls back to the other name.
  Future<void> _pauseResume({
    required bool pause,
    required List<String> hashes,
  }) async {
    final major = await _detectMajor();
    final v5 = pause ? 'api/v2/torrents/stop' : 'api/v2/torrents/start';
    final v4 = pause ? 'api/v2/torrents/pause' : 'api/v2/torrents/resume';
    final (first, second) = major >= 5 ? (v5, v4) : (v4, v5);
    final form = {'hashes': hashes.join('|')};
    try {
      await _postForm(first, form);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      await _postForm(second, form);
    }
  }

  @override
  Future<Result<String>> fetchVersion() => _guard(() async {
    final version = (await _get('api/v2/app/version')).trim();
    final mm = parseMajorMinor(version);
    if (mm != null) {
      _major = mm.$1;
      if (mm.$1 < 4 || (mm.$1 == 4 && mm.$2 < 1)) {
        throw const AppError(ErrorCategory.unsupportedVersion);
      }
    }
    return version;
  });

  @override
  Future<Result<List<Torrent>>> listTorrents() => _guard(() async {
    final body = await _get('api/v2/torrents/info');
    final parsed = await _parseOffIsolate(_runner, body);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Future<Result<TransferInfo>> transferInfo() =>
      _guard(() async => parseTransferInfo(await _get('api/v2/transfer/info')));

  @override
  Future<Result<void>> pause(List<String> hashes) =>
      _guard(() => _pauseResume(pause: true, hashes: hashes));

  @override
  Future<Result<void>> resume(List<String> hashes) =>
      _guard(() => _pauseResume(pause: false, hashes: hashes));

  @override
  Future<Result<void>> delete(
    List<String> hashes, {
    required bool deleteFiles,
  }) => _guard(() async {
    await _postForm('api/v2/torrents/delete', {
      'hashes': hashes.join('|'),
      'deleteFiles': deleteFiles ? 'true' : 'false',
    });
  });

  Map<String, String> _addFields(AddTorrentOptions o) => {
    if (o.savePath != null && o.savePath!.isNotEmpty) 'savepath': o.savePath!,
    if (o.category != null && o.category!.isNotEmpty) 'category': o.category!,
    if (o.tags.isNotEmpty) 'tags': o.tags.join(','),
    // v4 calls it `paused`, v5 `stopped`; each ignores the other.
    if (o.paused) ...{'paused': 'true', 'stopped': 'true'},
  };

  void _expectOk(String body) {
    // qBittorrent answers "Ok." or "Fails." (v4); empty on newer versions.
    if (body.trim() == 'Fails.') {
      throw const AppError(
        ErrorCategory.serverError,
        debugDetail: 'the server refused the torrent',
      );
    }
  }

  @override
  Future<Result<void>> addMagnetOrUrl(
    String link, {
    AddTorrentOptions options = const AddTorrentOptions(),
  }) => _guard(() async {
    _expectOk(
      await _postForm('api/v2/torrents/add', {
        'urls': link,
        ..._addFields(options),
      }),
    );
  });

  @override
  Future<Result<void>> addFile(
    Uint8List bytes, {
    required String fileName,
    AddTorrentOptions options = const AddTorrentOptions(),
  }) => _guard(() async {
    FormData form() => FormData.fromMap({
      ..._addFields(options),
      'torrents': MultipartFile.fromBytes(bytes, filename: 'upload.torrent'),
    });
    final body = await _send('POST', 'api/v2/torrents/add', data: form());
    _expectOk(body);
  });

  @override
  Future<Result<SpeedLimitsState>> globalLimits() => _guard(() async {
    final down = int.tryParse(
      (await _get('api/v2/transfer/downloadLimit')).trim(),
    );
    final up = int.tryParse((await _get('api/v2/transfer/uploadLimit')).trim());
    final mode = int.tryParse(
      (await _get('api/v2/transfer/speedLimitsMode')).trim(),
    );
    if (down == null || up == null) throw const FormatException('limit');
    return SpeedLimitsState(
      download: down < 0 ? 0 : down,
      upload: up < 0 ? 0 : up,
      alternativeActive: mode == null ? null : mode == 1,
    );
  });

  @override
  Future<Result<void>> setGlobalLimits(GlobalLimits limits) => _guard(() async {
    final d = limits.download;
    final u = limits.upload;
    if (d != null) {
      await _postForm('api/v2/transfer/setDownloadLimit', {'limit': '$d'});
    }
    if (u != null) {
      await _postForm('api/v2/transfer/setUploadLimit', {'limit': '$u'});
    }
  });

  @override
  Future<Result<void>> setAlternativeSpeed(bool enabled) => _guard(() async {
    final mode = int.tryParse(
      (await _get('api/v2/transfer/speedLimitsMode')).trim(),
    );
    if ((mode == 1) != enabled) {
      await _postForm('api/v2/transfer/toggleSpeedLimitsMode', const {});
    }
  });

  @override
  Future<Result<TorrentDetail>> torrentDetail(String hash) => _guard(() async {
    final infoBody = await _get(
      'api/v2/torrents/info',
      query: {'hashes': hash},
    );
    final parsed = parseTorrentList(infoBody);
    if (parsed.items.isEmpty) {
      throw const AppError(ErrorCategory.notFound);
    }
    final raw = jsonObject((jsonDecode(infoBody) as List).first);
    final props = jsonObject(
      jsonDecode(
        await _get('api/v2/torrents/properties', query: {'hash': hash}),
      ),
    );
    int? count(String key) {
      final v = props[key];
      return v is num && v >= 0 ? v.toInt() : null;
    }

    final avail = jsonNum(raw['availability']).toDouble();
    final savePath = props['save_path'];
    return TorrentDetail(
      torrent: parsed.items.first,
      savePath: savePath is String ? savePath : null,
      seeds: count('seeds'),
      seedsTotal: count('seeds_total'),
      peers: count('peers'),
      peersTotal: count('peers_total'),
      availability: avail >= 0 && raw['availability'] != null ? avail : null,
      downloaded: count('total_downloaded'),
      uploaded: count('total_uploaded'),
    );
  });
}
