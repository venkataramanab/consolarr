// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:security/security.dart';
import 'package:torrent_clients/src/client_support.dart';
import 'package:torrent_clients/src/models.dart';
import 'package:torrent_clients/src/torrent_actions.dart';
import 'package:torrent_clients/src/torrent_capabilities.dart';
import 'package:torrent_clients/src/torrent_client.dart';

/// Oldest RPC version the client works with (Transmission 2.80).
const transmissionMinRpcVersion = 14;

/// RPC version that introduced torrent `labels` (Transmission 3.0).
const transmissionLabelsRpcVersion = 16;

/// The `debugDetail` of the error for HTTP 403: the server refused the host
/// (its `rpc-host-whitelist` / `rpc-whitelist`), not the credentials.
const transmissionHostNotAllowedDetail = 'host not allowed by the server';

const _listFields = [
  'hashString',
  'name',
  'status',
  'percentDone',
  'totalSize',
  'rateDownload',
  'rateUpload',
  'uploadRatio',
  'eta',
  'addedDate',
  'error',
  'labels',
  'peersSendingToUs',
];

/// Keeps the `-1` (unavailable) and `-2` (infinite) sentinels, clamps the rest.
double _ratio(double v) =>
    v == -1 || v == -2 ? v : v.clamp(0.0, double.infinity);

/// Transmission's `status` field and friends -> [Torrent]. Throws
/// [FormatException] when `hashString` or `name` is missing or mistyped.
Torrent parseTransmissionTorrent(Map<String, Object?> json) {
  final hash = json['hashString'];
  final name = json['name'];
  if (hash is! String) throw const FormatException('hashString');
  if (name is! String) throw const FormatException('name');
  final progress = jsonNum(json['percentDone']).toDouble().clamp(0.0, 1.0);
  final status = json['status'];
  final eta = jsonNum(json['eta']);
  final added = jsonNum(json['addedDate']);
  final labels = json['labels'];
  final firstLabel =
      labels is List && labels.isNotEmpty && labels.first is String
      ? labels.first as String
      : null;
  return Torrent(
    hash: hash,
    name: name,
    state: TorrentState.fromTransmission(
      status is int ? status : null,
      progress: progress,
      // 1 and 2 are tracker warnings and errors; only 3 is a local error.
      hasError: jsonNum(json['error']).toInt() == 3,
      receiving:
          json['peersSendingToUs'] is! num ||
          jsonNum(json['peersSendingToUs']) > 0 ||
          jsonNum(json['rateDownload']) > 0,
    ),
    progress: progress,
    size: jsonNum(json['totalSize']).toInt(),
    dlSpeed: jsonNum(json['rateDownload']).toInt(),
    upSpeed: jsonNum(json['rateUpload']).toInt(),
    ratio: _ratio(jsonNum(json['uploadRatio']).toDouble()),
    eta: etaFromSeconds(eta),
    addedOn: epochSecondsToDate(added),
    label: firstLabel,
  );
}

/// Parses the `torrent-get` body. Top level so it can run in an isolate.
ParsedRows<Torrent> parseTransmissionList(String body) {
  final m = jsonObject(jsonDecode(body));
  final args = jsonObject(m['arguments']);
  final rows = args['torrents'];
  if (rows is! List) throw const FormatException('torrents');
  return parseRowsTolerant(
    rows,
    (e) => parseTransmissionTorrent(jsonObject(e)),
  );
}

/// Transmission RPC client (`/transmission/rpc`).
///
/// The `X-Transmission-Session-Id` is kept in memory only: a 409 response
/// carries the new id, the request is repeated once, and a second 409 is a
/// `server_error`. Basic credentials are added here (the torrent kinds get no
/// credential header from the app) and are never logged.
class TransmissionClient implements TorrentClient {
  TransmissionClient({
    required Dio dio,
    String? username,
    String? password,
    ParseRunner? parseRunner,
    this.onRowsSkipped,
  }) : _dio = dio,
       _runner = parseRunner ?? isolateRunner,
       _authorization = (username != null && username.isNotEmpty)
           ? 'Basic ${base64.encode(utf8.encode('$username:${password ?? ''}'))}'
           : null;

  final Dio _dio;
  final ParseRunner _runner;
  final String? _authorization;
  final void Function(int skipped)? onRowsSkipped;

  String? _sessionId;
  int _rpcVersion = 0;

  @override
  ServiceKind get kind => ServiceKind.transmission;

  @override
  TorrentCapabilities get capabilities => TorrentCapabilities(
    alternativeSpeed: true,
    // Transmission's "labels" are free-form tags.
    // Labels are silently dropped below RPC 16, so offer tags only once the
    // version is known (it is after the first successful list).
    tags: _rpcVersion >= transmissionLabelsRpcVersion,
    availability: false,
    speedLimitUnit: _kb,
  );

  /// The RPC version of the server; `0` until known.
  int get rpcVersion => _rpcVersion;

  @override
  void forgetSession() {
    _sessionId = null;
    _rpcVersion = 0;
  }

  Uri get _endpoint =>
      joinUri(Uri.parse(_dio.options.baseUrl), 'transmission/rpc');

  Future<Response<String>> _post(String body) => _dio.postUri<String>(
    _endpoint,
    data: body,
    options: Options(
      contentType: Headers.jsonContentType,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      headers: {
        if (_authorization != null) 'Authorization': _authorization,
        if (_sessionId != null) 'X-Transmission-Session-Id': _sessionId,
      },
    ),
  );

  /// One RPC call; returns the raw response body of a successful call.
  Future<String> _rpcRaw(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final body = jsonEncode({
      'method': method,
      if (arguments != null) 'arguments': arguments,
    });
    var response = await _post(body);
    if (response.statusCode == 409) {
      final id = response.headers.value('x-transmission-session-id');
      if (id == null || id.isEmpty) {
        throw const AppError(ErrorCategory.serverError);
      }
      _sessionId = id;
      response = await _post(body);
      if (response.statusCode == 409) {
        // The server keeps rejecting the id: never loop.
        throw const AppError(
          ErrorCategory.serverError,
          debugDetail: 'session id rejected twice',
        );
      }
    }
    final status = response.statusCode ?? 0;
    if (status == 403) {
      throw const AppError(
        ErrorCategory.authFailed,
        debugDetail: transmissionHostNotAllowedDetail,
      );
    }
    if (status == 401) throw const AppError(ErrorCategory.authFailed);
    if (status < 200 || status >= 300) throw appErrorFromStatus(status);
    final text = response.data ?? '';
    final decoded = jsonDecode(text);
    final result = jsonObject(decoded)['result'];
    if (result != 'success') {
      // The result text is server-supplied; keep it out of the error.
      throw const AppError(
        ErrorCategory.serverError,
        debugDetail: 'rpc result was not success',
      );
    }
    return text;
  }

  Future<Map<String, Object?>> _rpc(
    String method, [
    Map<String, Object?>? arguments,
  ]) async => jsonObject(
    jsonObject(jsonDecode(await _rpcRaw(method, arguments)))['arguments'],
  );

  @override
  Future<Result<String>> fetchVersion() => guardResult(() async {
    final args = await _rpc('session-get', {
      'fields': ['version', 'rpc-version'],
    });
    final rpc = jsonNum(args['rpc-version']).toInt();
    _rpcVersion = rpc;
    if (rpc != 0 && rpc < transmissionMinRpcVersion) {
      throw const AppError(ErrorCategory.unsupportedVersion);
    }
    final v = args['version'];
    if (v is! String) throw const FormatException('version');
    return v.split(' ').first;
  });

  @override
  Future<Result<List<Torrent>>> listTorrents() => guardResult(() async {
    await _ensureVersion();
    final body = await _rpcRaw('torrent-get', {'fields': _listFields});
    final parsed = await parseOffIsolate(_runner, body, parseTransmissionList);
    if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
    return parsed.items;
  });

  @override
  Future<Result<TransferInfo>> transferInfo() => guardResult(() async {
    final args = await _rpc('session-stats');
    final cumulative = jsonObject(args['cumulative-stats']);
    return TransferInfo(
      dlSpeed: jsonNum(args['downloadSpeed']).toInt(),
      upSpeed: jsonNum(args['uploadSpeed']).toInt(),
      dlTotal: jsonNum(cumulative['downloadedBytes']).toInt(),
      upTotal: jsonNum(cumulative['uploadedBytes']).toInt(),
    );
  });

  @override
  Future<Result<void>> pause(List<String> hashes) =>
      guardResult(() => _rpc('torrent-stop', {'ids': hashes}));

  @override
  Future<Result<void>> resume(List<String> hashes) =>
      guardResult(() => _rpc('torrent-start', {'ids': hashes}));

  @override
  Future<Result<void>> delete(
    List<String> hashes, {
    required bool deleteFiles,
  }) => guardResult(
    () => _rpc('torrent-remove', {
      'ids': hashes,
      'delete-local-data': deleteFiles,
    }),
  );

  Future<void> _ensureVersion() async {
    if (_rpcVersion != 0) return;
    final args = await _rpc('session-get', {
      'fields': ['rpc-version'],
    });
    _rpcVersion = jsonNum(args['rpc-version']).toInt();
  }

  Map<String, Object?> _addArgs(AddTorrentOptions o) => {
    if (o.savePath != null && o.savePath!.isNotEmpty)
      'download-dir': o.savePath,
    if (o.paused) 'paused': true,
    if (o.tags.isNotEmpty && _rpcVersion >= transmissionLabelsRpcVersion)
      'labels': o.tags,
  };

  @override
  Future<Result<void>> addMagnetOrUrl(
    String link, {
    AddTorrentOptions options = const AddTorrentOptions(),
  }) => guardResult(() async {
    if (options.tags.isNotEmpty) await _ensureVersion();
    await _rpc('torrent-add', {'filename': link, ..._addArgs(options)});
  });

  @override
  Future<Result<void>> addFile(
    Uint8List bytes, {
    required String fileName,
    AddTorrentOptions options = const AddTorrentOptions(),
  }) => guardResult(() async {
    if (options.tags.isNotEmpty) await _ensureVersion();
    await _rpc('torrent-add', {
      'metainfo': base64.encode(bytes),
      ..._addArgs(options),
    });
  });

  @override
  Future<Result<SpeedLimitsState>> globalLimits() => guardResult(() async {
    final a = await _rpc('session-get', {
      'fields': [
        'speed-limit-down',
        'speed-limit-down-enabled',
        'speed-limit-up',
        'speed-limit-up-enabled',
        'alt-speed-enabled',
      ],
    });
    int bytes(String limit, String enabled) =>
        a[enabled] == true ? jsonNum(a[limit]).toInt() * _kb : 0;
    return SpeedLimitsState(
      download: bytes('speed-limit-down', 'speed-limit-down-enabled'),
      upload: bytes('speed-limit-up', 'speed-limit-up-enabled'),
      alternativeActive: a['alt-speed-enabled'] is bool
          ? a['alt-speed-enabled'] as bool
          : null,
    );
  });

  /// Transmission counts speed limits in kB/s (1000 bytes).
  static const _kb = 1000;

  @override
  Future<Result<void>> setGlobalLimits(GlobalLimits limits) => guardResult(() {
    final d = limits.download;
    final u = limits.upload;
    return _rpc('session-set', {
      if (d != null) ...{
        'speed-limit-down-enabled': d > 0,
        if (d > 0) 'speed-limit-down': (d / _kb).ceil(),
      },
      if (u != null) ...{
        'speed-limit-up-enabled': u > 0,
        if (u > 0) 'speed-limit-up': (u / _kb).ceil(),
      },
    });
  });

  @override
  Future<Result<void>> setAlternativeSpeed(bool enabled) =>
      guardResult(() => _rpc('session-set', {'alt-speed-enabled': enabled}));

  @override
  Future<Result<TorrentDetail>> torrentDetail(String hash) =>
      guardResult(() async {
        final args = await _rpc('torrent-get', {
          'ids': [hash],
          'fields': [
            ..._listFields,
            'downloadDir',
            'peersConnected',
            'peersGettingFromUs',
            'trackerStats',
            'downloadedEver',
            'uploadedEver',
          ],
        });
        final rows = args['torrents'];
        if (rows is! List || rows.isEmpty) {
          throw const AppError(ErrorCategory.notFound);
        }
        final row = jsonObject(rows.first);
        final torrent = parseTransmissionTorrent(row);
        var seedsTotal = 0;
        var peersTotal = 0;
        var known = false;
        final stats = row['trackerStats'];
        if (stats is List) {
          for (final s in stats) {
            if (s is! Map) continue;
            final seeders = s['seederCount'];
            final leechers = s['leecherCount'];
            if (seeders is num && seeders > seedsTotal) {
              seedsTotal = seeders.toInt();
              known = true;
            }
            if (leechers is num && leechers > peersTotal) {
              peersTotal = leechers.toInt();
              known = true;
            }
          }
        }
        final dir = row['downloadDir'];
        return TorrentDetail(
          torrent: torrent,
          savePath: dir is String ? dir : null,
          seeds: row['peersSendingToUs'] is num
              ? jsonNum(row['peersSendingToUs']).toInt()
              : null,
          peers: row['peersGettingFromUs'] is num
              ? jsonNum(row['peersGettingFromUs']).toInt()
              : null,
          seedsTotal: known ? seedsTotal : null,
          peersTotal: known ? peersTotal : null,
          downloaded: row['downloadedEver'] is num
              ? jsonNum(row['downloadedEver']).toInt()
              : null,
          uploaded: row['uploadedEver'] is num
              ? jsonNum(row['uploadedEver']).toInt()
              : null,
        );
      });
}
