// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:torrent_clients/src/client_support.dart';
import 'package:torrent_clients/src/models.dart';
import 'package:torrent_clients/src/parse_runner.dart';
import 'package:torrent_clients/src/torrent_actions.dart';
import 'package:torrent_clients/src/torrent_capabilities.dart';
import 'package:torrent_clients/src/torrent_client.dart';

/// A daemon host the Deluge web UI can connect to. All strings are
/// server-supplied plain text.
class DelugeHost {
  const DelugeHost({required this.id, required this.host, required this.port});

  final String id;
  final String host;
  final int port;
}

/// Raised (inside a `Result.err`) when the web UI is not connected to a daemon
/// and more than one host exists: the user must pick one.
class DelugeHostRequired extends AppError {
  const DelugeHostRequired(this.hosts)
    : super(
        ErrorCategory.notFound,
        debugDetail: 'deluge web is not connected to a daemon host',
      );

  final List<DelugeHost> hosts;
}

/// The `debugDetail` of the error for a Deluge Web without any daemon host.
const delugeNoHostDetail = 'no daemon host configured';

/// Clients whose server needs the user to choose a daemon host.
abstract interface class DaemonHostSelection {
  /// The hosts the web UI knows.
  Future<Result<List<DelugeHost>>> hosts();

  /// Connects the web UI to the host with [id].
  Future<Result<void>> selectHost(String id);
}

const _statusKeys = [
  'name',
  'state',
  'progress',
  'total_size',
  'download_payload_rate',
  'upload_payload_rate',
  'ratio',
  'eta',
  'time_added',
  'label',
];

/// Deluge reports `-1` for "no ratio yet"; keep it, clamp other negatives.
double _delugeRatio(double v) => v == -1 ? v : v.clamp(0.0, double.infinity);

/// Parses one Deluge torrent status. Throws [FormatException] when the name
/// is missing or mistyped.
Torrent parseDelugeTorrent(String hash, Map<String, Object?> json) {
  final name = json['name'];
  if (name is! String) throw const FormatException('name');
  // Deluge reports progress as 0..100.
  final progress = (jsonNum(json['progress']).toDouble() / 100).clamp(0.0, 1.0);
  final eta = jsonNum(json['eta']);
  final added = jsonNum(json['time_added']);
  final label = json['label'];
  final rate = jsonNum(json['download_payload_rate']).toInt();
  return Torrent(
    hash: hash,
    name: name,
    state: TorrentState.fromDeluge(
      json['state'] is String ? json['state']! as String : null,
      progress: progress,
      receiving:
          rate > 0 ||
          json['num_seeds'] is! num ||
          jsonNum(json['num_seeds']) > 0,
    ),
    progress: progress,
    size: jsonNum(json['total_size']).toInt(),
    dlSpeed: rate,
    upSpeed: jsonNum(json['upload_payload_rate']).toInt(),
    ratio: _delugeRatio(jsonNum(json['ratio']).toDouble()),
    eta: etaFromSeconds(eta),
    addedOn: epochSecondsToDate(added),
    category: label is String && label.isNotEmpty ? label : null,
  );
}

/// Parses a `core.get_torrents_status` response body (the `result` map).
ParsedRows<Torrent> parseDelugeList(String body) {
  final m = jsonObject(jsonDecode(body));
  final result = m['result'];
  if (result is! Map) throw const FormatException('result');
  return parseRowsTolerant(result.entries, (e) {
    final entry = e! as MapEntry<Object?, Object?>;
    final key = entry.key;
    if (key is! String) throw const FormatException('hash');
    return parseDelugeTorrent(key, jsonObject(entry.value));
  });
}

/// A list response reduced to what must cross an isolate boundary: the rows
/// or a flag for the error kind (typed errors are built on the UI isolate).
class DelugeListOutcome {
  const DelugeListOutcome({
    this.rows,
    this.notAuthenticated = false,
    this.notConnected = false,
  });

  final ParsedRows<Torrent>? rows;
  final bool notAuthenticated;

  /// The web UI lost its daemon connection.
  final bool notConnected;
}

bool _isNotConnected(Object? message) =>
    message is String && message.toLowerCase().contains('not connected');

/// Whether [label] can be used by the Deluge label plugin after lowercasing
/// (`a-z`, `0-9`, `_`, `-`, `.`). Names with spaces or other characters are
/// refused by the plugin.
bool isValidDelugeLabel(String label) =>
    RegExp(r'^[a-z0-9_.\-]+$').hasMatch(label.toLowerCase());

/// Parses a `core.get_torrents_status` response, noting an authentication
/// error instead of throwing it. Top level so it can run in an isolate.
DelugeListOutcome parseDelugeListResponse(String body) {
  final m = jsonObject(jsonDecode(body));
  final error = m['error'];
  if (error is Map) {
    if (error['code'] == 1 || error['message'] == 'Not authenticated') {
      return const DelugeListOutcome(notAuthenticated: true);
    }
    if (_isNotConnected(error['message'])) {
      return const DelugeListOutcome(notConnected: true);
    }
    throw const FormatException('rpc error');
  }
  return DelugeListOutcome(rows: parseDelugeList(body));
}

/// Top level on purpose: the closure given to [runner] captures only [body],
/// never the client (its Dio/HttpClient cannot be sent to another isolate).
Future<DelugeListOutcome> _parseOffIsolate(ParseRunner runner, String body) =>
    body.length > isolateThresholdBytes
    ? runner(() => parseDelugeListResponse(body))
    : Future.value(parseDelugeListResponse(body));

/// Deluge web JSON-RPC client (`/json`).
///
/// `auth.login` returns a session cookie that lives in this object's memory
/// only (never logged, stored or put in a URL or an error). A rejected
/// session triggers one re-login. The web UI must be connected to a daemon:
/// with one known host the client connects to it, with several it fails with
/// [DelugeHostRequired] until the host is chosen ([selectHost]); the app
/// persists the chosen [hostId] and passes it back in. The Label plugin is
/// detected once; without it [capabilities] has no label model.
class DelugeClient implements TorrentClient, DaemonHostSelection {
  DelugeClient({
    required Dio dio,
    String? password,
    this.hostId,
    ParseRunner? parseRunner,
    this.onRowsSkipped,
    this.onHostConnected,
  }) : _dio = dio,
       _password = password,
       _runner = parseRunner ?? isolateRunner;

  final Dio _dio;
  final String? _password;
  final ParseRunner _runner;
  final void Function(int skipped)? onRowsSkipped;

  /// Called with the id of a host the client connected to by itself or by
  /// [selectHost], so the app can remember it.
  final void Function(String hostId)? onHostConnected;

  /// The preferred daemon host id (persisted by the app per server).
  String? hostId;

  String? _cookie;
  bool _connected = false;
  bool? _hasLabels;
  int _nextId = 1;

  @override
  ServiceKind get kind => ServiceKind.deluge;

  @override
  TorrentCapabilities get capabilities => TorrentCapabilities(
    labelModel: _hasLabels == true ? LabelModel.label : LabelModel.none,
    speedLimitUnit: _kib,
  );

  @override
  void forgetSession() {
    _cookie = null;
    _connected = false;
    _hasLabels = null;
  }

  Uri _url(String path) => joinUri(Uri.parse(_dio.options.baseUrl), path);

  Map<String, String> get _cookieHeader => {
    if (_cookie != null) 'Cookie': _cookie!,
  };

  /// A JSON-RPC call; the decoded body, or an [AppError].
  Future<Map<String, Object?>> _call(
    String method,
    List<Object?> params, {
    bool login = true,
    bool retry = true,
  }) async {
    if (login && _cookie == null) await _login();
    final body = await _post(method, params);
    final error = body['error'];
    if (error is Map) {
      final code = error['code'];
      final message = error['message'];
      // Deluge answers an expired session with "Not authenticated" (code 1).
      if (code == 1 || (message is String && message == 'Not authenticated')) {
        _cookie = null;
        _connected = false;
        if (retry) return _call(method, params, retry: false);
        throw const AppError(ErrorCategory.authFailed);
      }
      if (_isNotConnected(message) &&
          (method.startsWith('core.') || method.startsWith('label.'))) {
        _connected = false;
        if (retry) {
          await _ensureConnected();
          return _call(method, params, retry: false);
        }
        throw const AppError(ErrorCategory.networkUnreachable);
      }
      throw AppError(
        message is String && message.contains('Unknown')
            ? ErrorCategory.notFound
            : ErrorCategory.serverError,
        debugDetail: 'rpc error on $method',
      );
    }
    return body;
  }

  Future<Map<String, Object?>> _post(
    String method,
    List<Object?> params,
  ) async => jsonObject(jsonDecode(await _postText(method, params)));

  Future<String> _postText(String method, List<Object?> params) async {
    final response = await _dio.postUri<String>(
      _url('json'),
      data: jsonEncode({'method': method, 'params': params, 'id': _nextId++}),
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        headers: _cookieHeader,
      ),
    );
    _captureCookie(response);
    return response.data ?? '';
  }

  void _captureCookie(Response<String> response) {
    // A redirect to another origin must not plant a session cookie.
    if (!_sameOrigin(response.realUri, Uri.parse(_dio.options.baseUrl))) return;
    for (final c in response.headers['set-cookie'] ?? const <String>[]) {
      final pair = c.split(';').first.trim();
      if (pair.startsWith('_session_id=')) _cookie = pair;
    }
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      _port(a) == _port(b);

  static int _port(Uri u) =>
      u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);

  Future<void> _login() async {
    final password = _password;
    if (password == null || password.isEmpty) {
      throw const AppError(ErrorCategory.authFailed);
    }
    _cookie = null;
    final body = await _post('auth.login', [password]);
    if (body['result'] != true || _cookie == null) {
      _cookie = null;
      throw const AppError(ErrorCategory.authFailed);
    }
  }

  Future<Object?> _result(
    String method, [
    List<Object?> params = const [],
  ]) async => (await _call(method, params))['result'];

  /// Connects the web UI to a daemon when it is not yet connected.
  Future<void> _ensureConnected() async {
    if (_connected) return;
    if (await _result('web.connected') == true) {
      _connected = true;
      return;
    }
    final hosts = await _loadHosts();
    if (hosts.isEmpty) {
      throw const AppError(
        ErrorCategory.notFound,
        debugDetail: delugeNoHostDetail,
      );
    }
    final preferred = hostId;
    DelugeHost? chosen;
    if (preferred != null) {
      for (final h in hosts) {
        if (h.id == preferred) chosen = h;
      }
    }
    chosen ??= hosts.length == 1 ? hosts.first : null;
    if (chosen == null) throw DelugeHostRequired(hosts);
    await _connect(chosen.id);
  }

  Future<void> _connect(String id) async {
    await _result('web.connect', [id]);
    _connected = true;
    hostId = id;
    onHostConnected?.call(id);
  }

  Future<List<DelugeHost>> _loadHosts() async {
    final raw = await _result('web.get_hosts');
    if (raw is! List) throw const FormatException('hosts');
    final hosts = <DelugeHost>[];
    for (final h in raw) {
      if (h is List && h.length >= 3 && h[0] is String && h[1] is String) {
        hosts.add(
          DelugeHost(
            id: h[0] as String,
            host: h[1] as String,
            port: h[2] is num ? (h[2] as num).toInt() : 0,
          ),
        );
      }
    }
    return hosts;
  }

  @override
  Future<Result<List<DelugeHost>>> hosts() => guardResult(_loadHostsLoggedIn);

  Future<List<DelugeHost>> _loadHostsLoggedIn() async => _loadHosts();

  @override
  Future<Result<void>> selectHost(String id) => guardResult(() async {
    await _call('auth.check_session', const []);
    await _connect(id);
  });

  Future<void> _detectLabels() async {
    if (_hasLabels != null) return;
    final plugins = await _result('core.get_enabled_plugins');
    _hasLabels = plugins is List && plugins.contains('Label');
  }

  /// Runs [body] once connected to a daemon.
  Future<T> _connectedCall<T>(Future<T> Function() body) async {
    await _ensureConnected();
    return body();
  }

  @override
  Future<Result<String>> fetchVersion() => guardResult(() async {
    await _call('auth.check_session', const []);
    await _ensureConnected();
    Object? v;
    try {
      v = await _result('daemon.get_version');
    } on AppError catch (e) {
      if (e.category != ErrorCategory.notFound) rethrow;
      v = await _result('daemon.info');
    }
    if (v is! String) throw const FormatException('version');
    final mm = parseMajorMinor(v);
    if (mm != null && mm.$1 < 1) {
      throw const AppError(ErrorCategory.unsupportedVersion);
    }
    return v;
  });

  @override
  Future<Result<List<Torrent>>> listTorrents() => guardResult(
    () => _connectedCall(() async {
      await _detectLabels();
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_cookie == null) await _login();
        final body = await _postText('core.get_torrents_status', [
          <String, Object?>{},
          [..._statusKeys, 'num_seeds'],
        ]);
        final outcome = await _parseOffIsolate(_runner, body);
        final parsed = outcome.rows;
        if (parsed != null) {
          if (parsed.skipped > 0) onRowsSkipped?.call(parsed.skipped);
          return parsed.items;
        }
        if (outcome.notConnected) {
          // The daemon dropped: reconnect once, then give up as unreachable.
          _connected = false;
          if (attempt == 1) {
            throw const AppError(ErrorCategory.networkUnreachable);
          }
          await _ensureConnected();
          continue;
        }
        // Session expired: log in again once.
        _cookie = null;
        _connected = false;
        await _ensureConnected();
      }
      throw const AppError(ErrorCategory.authFailed);
    }),
  );

  @override
  Future<Result<TransferInfo>> transferInfo() => guardResult(
    () => _connectedCall(() async {
      final r = await _result('core.get_session_status', [
        [
          'payload_download_rate',
          'payload_upload_rate',
          'download_rate',
          'upload_rate',
          'total_download',
          'total_upload',
        ],
      ]);
      final m = jsonObject(r);
      int pick(String a, String b) =>
          m[a] is num ? jsonNum(m[a]).toInt() : jsonNum(m[b]).toInt();
      return TransferInfo(
        dlSpeed: pick('payload_download_rate', 'download_rate'),
        upSpeed: pick('payload_upload_rate', 'upload_rate'),
        dlTotal: jsonNum(m['total_download']).toInt(),
        upTotal: jsonNum(m['total_upload']).toInt(),
      );
    }),
  );

  @override
  Future<Result<void>> pause(List<String> hashes) => guardResult(
    () => _connectedCall(
      () => _bulk('core.pause_torrent', 'core.pause_torrents', hashes),
    ),
  );

  @override
  Future<Result<void>> resume(List<String> hashes) => guardResult(
    () => _connectedCall(
      () => _bulk('core.resume_torrent', 'core.resume_torrents', hashes),
    ),
  );

  Future<void> _bulk(String v1, String v2, List<String> hashes) async {
    Object? result;
    try {
      result = await _result(v1, [hashes]);
    } on AppError catch (e) {
      if (e.category != ErrorCategory.notFound) rethrow;
      result = await _result(v2, [hashes]);
    }
    // Deluge 2.x answers with the `[id, message]` pairs that failed.
    final failed = <String>[
      if (result is List)
        for (final f in result)
          if (f is List && f.isNotEmpty && f.first is String) f.first as String,
    ];
    _throwFailures(failed, hashes.length, ErrorCategory.serverError);
  }

  /// Nothing to do without failures; the plain error when every torrent
  /// failed; a [PartialActionFailure] otherwise.
  void _throwFailures(List<String> failed, int total, ErrorCategory category) {
    if (failed.isEmpty) return;
    if (failed.length >= total) throw AppError(category);
    throw PartialActionFailure(
      category: category,
      failed: failed,
      total: total,
    );
  }

  @override
  Future<Result<void>> delete(
    List<String> hashes, {
    required bool deleteFiles,
  }) => guardResult(
    () => _connectedCall(() async {
      final failed = <String>[];
      var category = ErrorCategory.serverError;
      for (var i = 0; i < hashes.length; i++) {
        try {
          await _result('core.remove_torrent', [hashes[i], deleteFiles]);
        } on AppError catch (e) {
          if (failed.isEmpty) category = e.category;
          if (e.category == ErrorCategory.serverError ||
              e.category == ErrorCategory.notFound) {
            failed.add(hashes[i]);
          } else {
            // The connection or session is gone: the rest cannot succeed.
            failed.addAll(hashes.sublist(i));
            break;
          }
        }
      }
      _throwFailures(failed, hashes.length, category);
    }),
  );

  Map<String, Object?> _options(AddTorrentOptions o) => {
    if (o.savePath != null && o.savePath!.isNotEmpty)
      'download_location': o.savePath,
    if (o.paused) 'add_paused': true,
  };

  /// Best effort: the torrent is already added, so a label problem is a
  /// warning ([AddWarning.labelNotApplied]) and never an error.
  Future<void> _applyLabel(String? hash, AddTorrentOptions o) async {
    final requested = o.category;
    if (requested == null || requested.isEmpty) return;
    try {
      await _detectLabels();
      if (_hasLabels != true) return;
      final label = requested.toLowerCase();
      if (hash == null || !isValidDelugeLabel(label)) {
        o.onWarning?.call(AddWarning.labelNotApplied);
        return;
      }
      final labels = await _result('label.get_labels');
      if (labels is List && !labels.contains(label)) {
        await _result('label.add', [label]);
      }
      await _result('label.set_torrent', [hash, label]);
    } on AppError {
      o.onWarning?.call(AddWarning.labelNotApplied);
    }
  }

  @override
  Future<Result<void>> addMagnetOrUrl(
    String link, {
    AddTorrentOptions options = const AddTorrentOptions(),
  }) => guardResult(
    () => _connectedCall(() async {
      final isMagnet = link.trimLeft().toLowerCase().startsWith('magnet:');
      final hash = await _result(
        isMagnet ? 'core.add_torrent_magnet' : 'core.add_torrent_url',
        [link, _options(options)],
      );
      if (hash == null || hash == false) {
        throw const AppError(
          ErrorCategory.serverError,
          debugDetail: 'the daemon refused the torrent',
        );
      }
      await _applyLabel(hash is String ? hash : null, options);
    }),
  );

  /// Upload through the web UI's `/upload` endpoint, then `web.add_torrents`.
  @override
  Future<Result<void>> addFile(
    Uint8List bytes, {
    required String fileName,
    AddTorrentOptions options = const AddTorrentOptions(),
  }) => guardResult(
    () => _connectedCall(() async {
      final wantsLabel =
          options.category != null && options.category!.isNotEmpty;
      final before = wantsLabel ? await _hashes() : null;
      final response = await _dio.postUri<String>(
        _url('upload'),
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'upload.torrent'),
        }),
        options: Options(
          responseType: ResponseType.plain,
          headers: _cookieHeader,
        ),
      );
      final up = jsonObject(jsonDecode(response.data ?? ''));
      final files = up['files'];
      if (up['success'] != true || files is! List || files.isEmpty) {
        throw const AppError(ErrorCategory.serverError);
      }
      await _result('web.add_torrents', [
        [
          {'path': files.first, 'options': _options(options)},
        ],
      ]);
      // The web call does not return the hash: the new torrent is the one
      // that was not in the list before.
      if (before != null) {
        await _applyLabel(await _newHash(before), options);
      }
    }),
  );

  Future<Set<String>?> _hashes() async {
    try {
      final r = await _result('core.get_torrents_status', [
        <String, Object?>{},
        ['name'],
      ]);
      if (r is! Map) return null;
      return {
        for (final k in r.keys)
          if (k is String) k,
      };
    } on AppError {
      return null;
    }
  }

  /// The single hash that is in the list now but was not in [before] (the web
  /// UI adds in the background, so look a few times); `null` when none or
  /// several appeared.
  Future<String?> _newHash(Set<String> before) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      final now = await _hashes();
      if (now == null) return null;
      final added = now.difference(before);
      if (added.length == 1) return added.single;
      if (added.length > 1) return null;
    }
    return null;
  }

  static const _kib = 1024;

  @override
  Future<Result<SpeedLimitsState>> globalLimits() => guardResult(
    () => _connectedCall(() async {
      final r = jsonObject(
        await _result('core.get_config_values', [
          ['max_download_speed', 'max_upload_speed'],
        ]),
      );
      int bytes(Object? kib) {
        final v = jsonNum(kib);
        return v <= 0 ? 0 : (v * _kib).round();
      }

      return SpeedLimitsState(
        download: bytes(r['max_download_speed']),
        upload: bytes(r['max_upload_speed']),
      );
    }),
  );

  @override
  Future<Result<void>> setAlternativeSpeed(bool enabled) async =>
      const Result.err(UnsupportedAction('setAlternativeSpeed'));

  @override
  Future<Result<void>> setGlobalLimits(GlobalLimits limits) => guardResult(
    () => _connectedCall(() async {
      double kib(int bytes) => bytes <= 0 ? -1 : bytes / _kib;
      final d = limits.download;
      final u = limits.upload;
      await _result('core.set_config', [
        {
          if (d != null) 'max_download_speed': kib(d),
          if (u != null) 'max_upload_speed': kib(u),
        },
      ]);
    }),
  );

  @override
  Future<Result<TorrentDetail>> torrentDetail(String hash) => guardResult(
    () => _connectedCall(() async {
      final r = await _result('core.get_torrent_status', [
        hash,
        [
          ..._statusKeys,
          'save_path',
          'total_seeds',
          'total_peers',
          'num_seeds',
          'num_peers',
          'distributed_copies',
          'all_time_download',
          'total_uploaded',
        ],
      ]);
      final m = jsonObject(r);
      if (m.isEmpty) throw const AppError(ErrorCategory.notFound);
      int? count(String key) => m[key] is num && (m[key] as num) >= 0
          ? (m[key] as num).toInt()
          : null;
      final copies = m['distributed_copies'];
      final path = m['save_path'];
      return TorrentDetail(
        torrent: parseDelugeTorrent(hash, m),
        savePath: path is String ? path : null,
        seeds: count('num_seeds'),
        seedsTotal: count('total_seeds'),
        peers: count('num_peers'),
        peersTotal: count('total_peers'),
        availability: copies is num && copies >= 0 ? copies.toDouble() : null,
        downloaded: count('all_time_download'),
        uploaded: count('total_uploaded'),
      );
    }),
  );
}
