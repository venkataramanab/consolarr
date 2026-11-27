// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:torrent_clients/src/client_support.dart';
import 'package:torrent_clients/torrent_clients.dart';

const _hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Awkward numbers a hostile or buggy server might send for a date or span.
final _numbers = <Object?>[
  0,
  -1,
  1700000000,
  253402300800, // year 10000
  8640000000000000,
  9223372036854775807,
  -9223372036854775807,
  1e300,
  -1e300,
  1.5e12,
  'x',
  null,
  true,
  [1],
  {'a': 1},
];

Object? _pick(Random r) => _numbers[r.nextInt(_numbers.length)];

void main() {
  test('a huge addedDate never throws: the row stays, the date is null', () {
    for (final v in <Object>[
      8640000000000000,
      9223372036854775807,
      1e300,
      -1e300,
    ]) {
      final q = parseTorrentList(
        jsonEncode([
          {'hash': _hash, 'name': 'Example', 'added_on': v},
        ]),
      );
      expect(q.items, hasLength(1), reason: 'qBittorrent $v');
      expect(q.items.single.addedOn, isNull);
      final t = parseTransmissionList(
        jsonEncode({
          'arguments': {
            'torrents': [
              {'hashString': _hash, 'name': 'Example', 'addedDate': v},
            ],
          },
        }),
      );
      expect(t.items, hasLength(1), reason: 'Transmission $v');
      expect(t.items.single.addedOn, isNull);
      final d = parseDelugeList(
        jsonEncode({
          'result': {
            _hash: {'name': 'Example', 'time_added': v},
          },
        }),
      );
      expect(d.items, hasLength(1), reason: 'Deluge $v');
      expect(d.items.single.addedOn, isNull);
    }
  });

  test('a sane addedDate still parses', () {
    final q = parseTorrentList(
      jsonEncode([
        {'hash': _hash, 'name': 'Example', 'added_on': 1700000000},
      ]),
    );
    expect(
      q.items.single.addedOn,
      DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
  });

  test('fuzz: random odd values in numeric fields never throw', () {
    final r = Random(42);
    for (var i = 0; i < 500; i++) {
      final qb = jsonEncode([
        {
          'hash': _hash,
          'name': 'Example',
          'added_on': _pick(r),
          'eta': _pick(r),
          'progress': _pick(r),
          'size': _pick(r),
          'ratio': _pick(r),
        },
      ]);
      expect(() => parseTorrentList(qb), returnsNormally, reason: qb);
      final tr = jsonEncode({
        'arguments': {
          'torrents': [
            {
              'hashString': _hash,
              'name': 'Example',
              'addedDate': _pick(r),
              'eta': _pick(r),
              'percentDone': _pick(r),
              'totalSize': _pick(r),
              'uploadRatio': _pick(r),
              'error': _pick(r),
              'labels': _pick(r),
            },
          ],
        },
      });
      expect(() => parseTransmissionList(tr), returnsNormally, reason: tr);
      final dl = jsonEncode({
        'result': {
          _hash: {
            'name': 'Example',
            'time_added': _pick(r),
            'eta': _pick(r),
            'progress': _pick(r),
            'total_size': _pick(r),
            'ratio': _pick(r),
          },
        },
      });
      expect(() => parseDelugeList(dl), returnsNormally, reason: dl);
    }
  });

  group('guardResult', () {
    test('an unexpected programming error is parse_error', () async {
      for (final e in <Object>[
        RangeError('x'),
        StateError('x'),
        ArgumentError('x'),
        UnsupportedError('x'),
      ]) {
        final r = await guardResult<int>(() async => throw e);
        expect(r.errorOrNull?.category, ErrorCategory.parseError, reason: '$e');
      }
    });

    test('network failures stay network failures', () async {
      final r = await guardResult<int>(
        () async => throw const SocketException('down'),
      );
      expect(r.errorOrNull?.category, ErrorCategory.networkUnreachable);
    });
  });
}
