// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support/fake_adapter.dart';
import 'support/fake_servers.dart';

Future<T> _inline<T>(T Function() work) async => work();

TransmissionClient _client(FakeTransmission s) => TransmissionClient(
  dio: dioWith(s.adapter, base: 'https://transmission.example'),
  parseRunner: _inline,
);

Torrent _row(Map<String, Object?> extra) => parseTransmissionTorrent({
  'hashString': 'a' * 40,
  'name': 'Example',
  'status': 4,
  'percentDone': 0.5,
  'peersSendingToUs': 2,
  ...extra,
});

void main() {
  group('error field', () {
    test('1 and 2 are tracker warnings and errors, not a torrent error', () {
      expect(_row({'error': 1}).state, TorrentState.downloading);
      expect(_row({'error': 2}).state, TorrentState.downloading);
    });

    test('3 is a local error', () {
      expect(_row({'error': 3}).state, TorrentState.error);
    });
  });

  group('ratio', () {
    test('-1 is unknown, -2 is infinite, others are plain', () {
      expect(_row({'uploadRatio': -1}).ratioUnknown, isTrue);
      expect(_row({'uploadRatio': -2}).ratioInfinite, isTrue);
      final plain = _row({'uploadRatio': 1.5});
      expect(plain.ratio, 1.5);
      expect(plain.ratioUnknown, isFalse);
      expect(plain.ratioInfinite, isFalse);
      // Any other negative number is treated as zero.
      final odd = _row({'uploadRatio': -7});
      expect(odd.ratio, 0);
      expect(odd.ratioUnknown, isFalse);
    });
  });

  group('RPC version and tags', () {
    test('tags are not offered until the version is known', () async {
      final c = _client(FakeTransmission());
      expect(c.capabilities.tags, isFalse);
      await c.listTorrents();
      expect(c.capabilities.tags, isTrue);
      expect(c.rpcVersion, 17);
    });

    test('RPC 14 never offers tags', () async {
      final c = _client(FakeTransmission(rpcVersion: 14));
      await c.listTorrents();
      expect(c.capabilities.tags, isFalse);
    });
  });

  group('403', () {
    test('is auth_failed with the host whitelist detail', () async {
      final c = TransmissionClient(
        dio: dioWith(
          FakeAdapter.fixed('Forbidden', status: 403),
          base: 'https://t.example',
        ),
      );
      final e = (await c.listTorrents()).errorOrNull!;
      expect(e.category, ErrorCategory.authFailed);
      expect(e.debugDetail, transmissionHostNotAllowedDetail);
    });

    test('401 keeps the plain credentials error', () async {
      final c = TransmissionClient(
        dio: dioWith(
          FakeAdapter.fixed('', status: 401),
          base: 'https://t.example',
        ),
      );
      final e = (await c.listTorrents()).errorOrNull!;
      expect(e.category, ErrorCategory.authFailed);
      expect(e.debugDetail, isNot(transmissionHostNotAllowedDetail));
    });
  });

  test('speed limit unit per client', () {
    expect(
      TransmissionClient(dio: dioWith(FakeTransmission().adapter))
          .capabilities
          .speedLimitUnit,
      1000,
    );
    expect(jsonEncode(const TorrentCapabilities().speedLimitUnit), '1');
  });
}
