// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

class _FakeClient implements TorrentClient {
  _FakeClient(this._result);
  final Result<String> _result;

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
  test('TorrentClient reports version or a typed error', () async {
    final ok = await _FakeClient(const Result.ok('4.6.0')).fetchVersion();
    expect(ok.valueOrNull, '4.6.0');
    final err = await _FakeClient(
      const Result.err(AppError(ErrorCategory.authFailed)),
    ).fetchVersion();
    expect(err.errorOrNull?.category, ErrorCategory.authFailed);
  });
}
