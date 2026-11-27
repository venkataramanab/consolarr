// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:dio/dio.dart';

import 'fake_adapter.dart';

/// Hand-made fake data only (`*.example`, "Example Linux ISO").
const exampleHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const exampleMagnet =
    'magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    '&dn=Example+Linux+ISO&tr=https%3A%2F%2Ftracker.example%2Fannounce%3Fpasskey%3Dsecret-passkey';
const secretPasskey = 'secret-passkey';

class FakeTorrent {
  FakeTorrent(this.hash, this.name, {this.progress = 0.5, this.paused = false});
  final String hash;
  final String name;
  double progress;
  bool paused;
  String? label;
  String? savePath = '/downloads/example';
}

/// What every fake server exposes to the shared contract suite.
abstract class FakeServer {
  FakeAdapter get adapter;
  List<FakeTorrent> get torrents;

  /// The delete flag of the last remove call (`null` = none yet).
  bool? lastDeleteData;
  int downLimit = 0;
  int upLimit = 0;
  bool alt = false;
  bool paused = false;
  int addCalls = 0;
  String? lastLabel;
  String? lastSavePath;
  bool lastAddPaused = false;
}

/// qBittorrent WebUI API v2 (v4 or v5 naming).
class FakeQBittorrent extends FakeServer {
  FakeQBittorrent({this.version = 'v4.6.3'}) {
    torrents.add(FakeTorrent(exampleHash, 'Example Linux ISO'));
  }

  final String version;
  @override
  final List<FakeTorrent> torrents = [];
  final List<String> paths = [];
  bool get _v5 => version.startsWith('v5') || version.startsWith('5');

  @override
  late final FakeAdapter adapter = FakeAdapter(_handle);

  static const cookie = 'SID=fake-session';

  static Map<String, String> _form(Object? data) {
    if (data is! String) return const {};
    return {
      for (final p in data.split('&'))
        if (p.contains('='))
          Uri.decodeQueryComponent(p.split('=').first):
              Uri.decodeQueryComponent(p.substring(p.indexOf('=') + 1)),
    };
  }

  ResponseBody _handle(RequestOptions o) {
    final path = o.uri.path.split('/api/v2/').last;
    paths.add(path);
    if (path == 'auth/login') {
      return FakeAdapter.reply(
        'Ok.',
        headers: {
          'set-cookie': ['$cookie; HttpOnly; path=/'],
        },
      );
    }
    if (!'${o.headers['Cookie']}'.contains(cookie)) {
      return FakeAdapter.reply('Forbidden', status: 403);
    }
    final f = _form(o.data);
    switch (path) {
      case 'app/version':
        return FakeAdapter.reply(version);
      case 'torrents/info':
        final only = o.uri.queryParameters['hashes'];
        return FakeAdapter.reply(
          jsonEncode([
            for (final t in torrents)
              if (only == null || only == t.hash)
                {
                  'hash': t.hash,
                  'name': t.name,
                  'state': t.paused
                      ? (_v5 ? 'stoppedDL' : 'pausedDL')
                      : 'downloading',
                  'progress': t.progress,
                  'size': 1000,
                  'dlspeed': t.paused ? 0 : 100,
                  'upspeed': 0,
                  'ratio': 0.5,
                  'eta': 60,
                  'added_on': 1700000000,
                  'category': t.label ?? '',
                  'availability': 1.5,
                },
          ]),
        );
      case 'torrents/properties':
        return FakeAdapter.reply(
          jsonEncode({
            'save_path': '/downloads/example',
            'seeds': 3,
            'seeds_total': 10,
            'peers': 2,
            'peers_total': 7,
            'total_downloaded': 500,
            'total_uploaded': 250,
          }),
        );
      case 'transfer/info':
        return FakeAdapter.reply(
          jsonEncode({
            'dl_info_speed': 100,
            'up_info_speed': 10,
            'dl_info_data': 1,
            'up_info_data': 2,
          }),
        );
      case 'torrents/pause' || 'torrents/stop':
        if ((path == 'torrents/stop') != _v5) {
          return FakeAdapter.reply('Not Found', status: 404);
        }
        _each(f['hashes'], (t) => t.paused = true);
        return FakeAdapter.reply('');
      case 'torrents/resume' || 'torrents/start':
        if ((path == 'torrents/start') != _v5) {
          return FakeAdapter.reply('Not Found', status: 404);
        }
        _each(f['hashes'], (t) => t.paused = false);
        return FakeAdapter.reply('');
      case 'torrents/delete':
        lastDeleteData = f['deleteFiles'] == 'true';
        final hashes = (f['hashes'] ?? '').split('|');
        torrents.removeWhere((t) => hashes.contains(t.hash));
        return FakeAdapter.reply('');
      case 'torrents/add':
        addCalls++;
        final d = o.data;
        Map<String, String> fields = f;
        if (d is FormData) {
          fields = {for (final e in d.fields) e.key: e.value};
        }
        lastLabel = fields['category'];
        lastSavePath = fields['savepath'];
        lastAddPaused =
            fields['paused'] == 'true' || fields['stopped'] == 'true';
        torrents.add(
          FakeTorrent('c' * 40, 'Example Added', paused: lastAddPaused)
            ..label = lastLabel,
        );
        return FakeAdapter.reply('Ok.');
      case 'transfer/downloadLimit':
        return FakeAdapter.reply('$downLimit');
      case 'transfer/uploadLimit':
        return FakeAdapter.reply('$upLimit');
      case 'transfer/setDownloadLimit':
        downLimit = int.parse(f['limit']!);
        return FakeAdapter.reply('');
      case 'transfer/setUploadLimit':
        upLimit = int.parse(f['limit']!);
        return FakeAdapter.reply('');
      case 'transfer/speedLimitsMode':
        return FakeAdapter.reply(alt ? '1' : '0');
      case 'transfer/toggleSpeedLimitsMode':
        alt = !alt;
        return FakeAdapter.reply('');
    }
    return FakeAdapter.reply('Not Found', status: 404);
  }

  void _each(String? hashes, void Function(FakeTorrent) f) {
    final set = (hashes ?? '').split('|');
    for (final t in torrents) {
      if (set.contains(t.hash) || hashes == 'all') f(t);
    }
  }
}

/// Transmission RPC with the session-id handshake.
class FakeTransmission extends FakeServer {
  FakeTransmission({this.rpcVersion = 17}) {
    torrents.add(FakeTorrent(exampleHash, 'Example Linux ISO'));
  }

  final int rpcVersion;
  @override
  final List<FakeTorrent> torrents = [];
  String sessionId = 'session-one';
  final List<RequestOptions> seen = [];
  String? expectedAuth;

  /// Number of upcoming requests answered with 409 regardless of the id.
  int stormRemaining = 0;
  List<String> lastLabels = const [];
  bool? lastDeleteFlag;
  String? lastMetainfo;

  @override
  late final FakeAdapter adapter = FakeAdapter(_handle);

  ResponseBody _handle(RequestOptions o) {
    seen.add(o);
    if (expectedAuth != null && o.headers['Authorization'] != expectedAuth) {
      return FakeAdapter.reply('', status: 401);
    }
    final hasId = o.headers['X-Transmission-Session-Id'] == sessionId;
    if (stormRemaining > 0 || !hasId) {
      if (stormRemaining > 0) stormRemaining--;
      return FakeAdapter.reply(
        '',
        status: 409,
        headers: {
          'x-transmission-session-id': [sessionId],
        },
      );
    }
    final req = jsonDecode(o.data as String) as Map<String, Object?>;
    final args = (req['arguments'] as Map?)?.cast<String, Object?>() ?? {};
    Object ok([Map<String, Object?> a = const {}]) => {
      'result': 'success',
      'arguments': a,
    };
    Object body;
    switch (req['method']) {
      case 'session-get':
        body = ok({
          'version': '4.0.5 (abcdef)',
          'rpc-version': rpcVersion,
          'speed-limit-down': downLimit ~/ 1000,
          'speed-limit-down-enabled': downLimit > 0,
          'speed-limit-up': upLimit ~/ 1000,
          'speed-limit-up-enabled': upLimit > 0,
          'alt-speed-enabled': alt,
        });
      case 'session-stats':
        body = ok({
          'downloadSpeed': 100,
          'uploadSpeed': 10,
          'cumulative-stats': {'downloadedBytes': 1, 'uploadedBytes': 2},
        });
      case 'torrent-get':
        final ids = (args['ids'] as List?)?.cast<String>();
        body = ok({
          'torrents': [
            for (final t in torrents)
              if (ids == null || ids.contains(t.hash))
                {
                  'hashString': t.hash,
                  'name': t.name,
                  'status': t.paused ? 0 : 4,
                  'percentDone': t.progress,
                  'totalSize': 1000,
                  'rateDownload': t.paused ? 0 : 100,
                  'rateUpload': 0,
                  'uploadRatio': 0.5,
                  'eta': 60,
                  'addedDate': 1700000000,
                  'error': 0,
                  'labels': t.label == null ? [] : [t.label],
                  'peersSendingToUs': 2,
                  'peersGettingFromUs': 1,
                  'downloadDir': '/downloads/example',
                  'trackerStats': [
                    {'seederCount': 10, 'leecherCount': 7},
                  ],
                  'downloadedEver': 500,
                  'uploadedEver': 250,
                },
          ],
        });
      case 'torrent-stop' || 'torrent-start':
        final ids = (args['ids'] as List).cast<String>();
        for (final t in torrents) {
          if (ids.contains(t.hash)) t.paused = req['method'] == 'torrent-stop';
        }
        body = ok();
      case 'torrent-remove':
        lastDeleteFlag = args['delete-local-data'] as bool?;
        lastDeleteData = lastDeleteFlag;
        final ids = (args['ids'] as List).cast<String>();
        torrents.removeWhere((t) => ids.contains(t.hash));
        body = ok();
      case 'torrent-add':
        addCalls++;
        lastSavePath = args['download-dir'] as String?;
        lastAddPaused = args['paused'] == true;
        lastLabels = ((args['labels'] as List?) ?? const []).cast<String>();
        lastMetainfo = args['metainfo'] as String?;
        torrents.add(
          FakeTorrent('c' * 40, 'Example Added', paused: lastAddPaused),
        );
        body = ok({
          'torrent-added': {'hashString': 'c' * 40},
        });
      case 'session-set':
        if (args.containsKey('speed-limit-down-enabled')) {
          downLimit = args['speed-limit-down-enabled'] == true
              ? (args['speed-limit-down'] as int) * 1000
              : 0;
        }
        if (args.containsKey('speed-limit-up-enabled')) {
          upLimit = args['speed-limit-up-enabled'] == true
              ? (args['speed-limit-up'] as int) * 1000
              : 0;
        }
        if (args.containsKey('alt-speed-enabled')) {
          alt = args['alt-speed-enabled'] as bool;
        }
        body = ok();
      default:
        body = {'result': 'method name not recognized'};
    }
    return FakeAdapter.reply(jsonEncode(body));
  }
}

/// Deluge web JSON-RPC.
class FakeDeluge extends FakeServer {
  FakeDeluge({
    this.connected = true,
    this.hosts = const [
      ['host1', 'daemon.example', 58846, 'Online'],
    ],
    this.labelPlugin = true,
  }) {
    torrents.add(FakeTorrent(exampleHash, 'Example Linux ISO'));
  }

  bool connected;
  List<List<Object?>> hosts;
  bool labelPlugin;
  @override
  final List<FakeTorrent> torrents = [];
  final List<String> methods = [];
  String cookie = 'sid-1';
  int logins = 0;
  String? connectedTo;
  String password = 'test-password';
  final List<String> labels = [];
  int uploads = 0;

  /// Torrent ids `core.remove_torrent` refuses.
  final Set<String> failRemove = {};

  /// Torrent ids `core.pause_torrent` reports as failed (Deluge 2.x answers
  /// with a list of `[id, message]`).
  final Set<String> failPause = {};

  /// New torrents are inserted first (so they are not the "last" row).
  bool addPrepends = false;

  /// The hash the next added torrent gets.
  String addedHash = 'c' * 40;

  /// Torrent ids the label plugin is asked to label.
  final List<String> labelled = [];

  /// The daemon connection dropped: `core.*` answers "Not connected".
  void dropDaemon() => connected = false;

  @override
  late final FakeAdapter adapter = FakeAdapter(_handle);

  /// Invalidates the session (the next call is "Not authenticated").
  void expireSession() => cookie = 'sid-${logins + 100}';

  ResponseBody _handle(RequestOptions o) {
    if (o.uri.path.endsWith('/upload')) {
      uploads++;
      return FakeAdapter.reply(
        jsonEncode({
          'success': true,
          'files': ['/tmp/delugeweb-x/upload.torrent'],
        }),
      );
    }
    final req = jsonDecode(o.data as String) as Map<String, Object?>;
    final method = req['method']! as String;
    final params = (req['params'] as List).cast<Object?>();
    methods.add(method);
    Object? result;
    if (method == 'auth.login') {
      if (params.first != password) {
        return FakeAdapter.reply(
          jsonEncode({'result': false, 'error': null, 'id': req['id']}),
        );
      }
      logins++;
      cookie = 'sid-$logins';
      return FakeAdapter.reply(
        jsonEncode({'result': true, 'error': null, 'id': req['id']}),
        headers: {
          'set-cookie': ['_session_id=$cookie; Path=/; HttpOnly'],
        },
      );
    }
    if (!'${o.headers['Cookie']}'.contains('_session_id=$cookie')) {
      return FakeAdapter.reply(
        jsonEncode({
          'result': null,
          'error': {'message': 'Not authenticated', 'code': 1},
          'id': req['id'],
        }),
      );
    }
    if (!connected && method.startsWith('core.')) {
      return FakeAdapter.reply(
        jsonEncode({
          'result': null,
          'error': {'message': 'Not connected.', 'code': 4},
          'id': req['id'],
        }),
      );
    }
    switch (method) {
      case 'auth.check_session':
        result = true;
      case 'web.connected':
        result = connected;
      case 'web.get_hosts':
        result = hosts;
      case 'web.connect':
        connected = true;
        connectedTo = params.first as String;
        result = [];
      case 'daemon.get_version':
        result = '2.1.1';
      case 'core.get_enabled_plugins':
        result = labelPlugin ? ['Label'] : <String>[];
      case 'core.get_torrents_status':
        result = {
          for (final t in torrents)
            t.hash: {
              'name': t.name,
              'state': t.paused ? 'Paused' : 'Downloading',
              'progress': t.progress * 100,
              'total_size': 1000,
              'download_payload_rate': t.paused ? 0 : 100,
              'upload_payload_rate': 0,
              'ratio': 0.5,
              'eta': 60,
              'time_added': 1700000000.0 + torrents.indexOf(t),
              'label': t.label ?? '',
              'num_seeds': 2,
            },
        };
      case 'core.get_torrent_status':
        final t = torrents.where((t) => t.hash == params.first).firstOrNull;
        result = t == null
            ? <String, Object?>{}
            : {
                'name': t.name,
                'state': 'Downloading',
                'progress': t.progress * 100,
                'total_size': 1000,
                'download_payload_rate': 100,
                'upload_payload_rate': 0,
                'ratio': 0.5,
                'eta': 60,
                'time_added': 1700000000.0,
                'save_path': '/downloads/example',
                'num_seeds': 3,
                'total_seeds': 10,
                'num_peers': 2,
                'total_peers': 7,
                'distributed_copies': 1.5,
                'all_time_download': 500,
                'total_uploaded': 250,
              };
      case 'core.get_session_status':
        result = {
          'payload_download_rate': 100,
          'payload_upload_rate': 10,
          'total_download': 1,
          'total_upload': 2,
        };
      case 'core.pause_torrent' || 'core.resume_torrent':
        final ids = (params.first! as List).cast<String>();
        final failed = <List<String>>[];
        for (final t in torrents) {
          if (!ids.contains(t.hash)) continue;
          if (failPause.contains(t.hash)) {
            failed.add([t.hash, 'Torrent is in an invalid state']);
          } else {
            t.paused = method == 'core.pause_torrent';
          }
        }
        if (failed.isNotEmpty) result = failed;
      case 'core.remove_torrent':
        if (failRemove.contains(params[0])) {
          return FakeAdapter.reply(
            jsonEncode({
              'result': null,
              'error': {'message': 'Torrent does not exist', 'code': 4},
              'id': req['id'],
            }),
          );
        }
        lastDeleteData = params[1] as bool;
        torrents.removeWhere((t) => t.hash == params[0]);
        result = true;
      case 'core.add_torrent_magnet' || 'core.add_torrent_url':
        result = _add(params[1] as Map);
      case 'web.add_torrents':
        final item = ((params.first! as List).first as Map);
        _add(item['options'] as Map);
        result = true;
      case 'core.get_config_values':
        result = {
          'max_download_speed': downLimit <= 0 ? -1.0 : downLimit / 1024,
          'max_upload_speed': upLimit <= 0 ? -1.0 : upLimit / 1024,
        };
      case 'core.set_config':
        final c = params.first! as Map;
        if (c.containsKey('max_download_speed')) {
          final v = (c['max_download_speed'] as num).toDouble();
          downLimit = v < 0 ? 0 : (v * 1024).round();
        }
        if (c.containsKey('max_upload_speed')) {
          final v = (c['max_upload_speed'] as num).toDouble();
          upLimit = v < 0 ? 0 : (v * 1024).round();
        }
      case 'label.get_labels':
        result = labels;
      case 'label.add':
        final name = params.first! as String;
        if (!RegExp(r'^[a-z0-9_\-.]+$').hasMatch(name)) {
          return FakeAdapter.reply(
            jsonEncode({
              'result': null,
              'error': {
                'message': 'Invalid label, valid characters:[a-z0-9_-]',
                'code': 4,
              },
              'id': req['id'],
            }),
          );
        }
        labels.add(name);
      case 'label.set_torrent':
        labelled.add(params[0]! as String);
        lastLabel = params[1] as String;
        for (final t in torrents) {
          if (t.hash == params[0]) t.label = lastLabel;
        }
      default:
        return FakeAdapter.reply(
          jsonEncode({
            'result': null,
            'error': {'message': 'Unknown method', 'code': 2},
            'id': req['id'],
          }),
        );
    }
    return FakeAdapter.reply(
      jsonEncode({'result': result, 'error': null, 'id': req['id']}),
    );
  }

  String _add(Map options) {
    addCalls++;
    lastSavePath = options['download_location'] as String?;
    lastAddPaused = options['add_paused'] == true;
    final added = FakeTorrent(
      addedHash,
      'Example Added',
      paused: lastAddPaused,
    );
    if (addPrepends) {
      torrents.insert(0, added);
    } else {
      torrents.add(added);
    }
    return addedHash;
  }
}
