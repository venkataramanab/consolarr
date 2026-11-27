// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

class _FakeClient with UnsupportedTorrentActions implements TorrentClient {
  _FakeClient(this._result);
  final Result<String> _result;

  @override
  void forgetSession() {}

  @override
  ServiceKind get kind => ServiceKind.qbittorrent;

  @override
  Future<Result<String>> fetchVersion() async => _result;

  @override
  Future<Result<List<Torrent>>> listTorrents() async => const Result.ok([]);

  @override
  Future<Result<TransferInfo>> transferInfo() async =>
      const Result.err(AppError(ErrorCategory.networkUnreachable));
}

void main() {
  test(
    'actions a client does not implement fail with UnsupportedAction',
    () async {
      final c = _FakeClient(const Result.ok('4.6.0'));
      final results = <Result<Object?>>[
        await c.pause(const ['h']),
        await c.resume(const ['h']),
        await c.delete(const ['h'], deleteFiles: true),
        await c.addMagnetOrUrl('magnet:?xt=urn:btih:example'),
        await c.addFile(Uint8List(0), fileName: 'example.torrent'),
        await c.setGlobalLimits(const GlobalLimits(download: 1)),
        await c.torrentDetail('h'),
        await c.globalLimits(),
        await c.setAlternativeSpeed(true),
      ];
      for (final r in results) {
        final error = r.errorOrNull;
        expect(error, isA<UnsupportedAction>());
        expect(error!.category, ErrorCategory.unsupportedVersion);
        expect(error.debugDetail, startsWith('unsupported action: '));
      }
    },
  );

  test('TorrentClient reports version or a typed error', () async {
    final ok = await _FakeClient(const Result.ok('4.6.0')).fetchVersion();
    expect(ok.valueOrNull, '4.6.0');
    final err = await _FakeClient(
      const Result.err(AppError(ErrorCategory.authFailed)),
    ).fetchVersion();
    expect(err.errorOrNull?.category, ErrorCategory.authFailed);
  });
}
