// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:isolate';

import 'package:arr_api/arr_api.dart';
import 'package:test/test.dart';

import '../support/fake_adapter.dart';

/// A fake adapter that, like the real `HttpClient` adapter, cannot be sent to
/// another isolate.
class _UnsendableAdapter extends FakeAdapter {
  _UnsendableAdapter(String body) : super((_) => FakeAdapter.reply(body));

  final ReceivePort port = ReceivePort();

  @override
  void close({bool force = false}) => port.close();
}

String _big(Map<String, Object?> Function(int i) row, {bool paged = false}) {
  final rows = [for (var i = 1; i <= 1200; i++) row(i)];
  final body = jsonEncode(
    paged
        ? {
            'page': 1,
            'pageSize': 1200,
            'totalRecords': rows.length,
            'records': rows,
          }
        : rows,
  );
  expect(body.length, greaterThan(ArrClientBase.isolateThresholdBytes));
  return body;
}

RadarrClient _client(String body) => RadarrClient(
  dio: dioWith(_UnsendableAdapter(body), base: 'https://radarr.example'),
  parseRunner: isolateParseRunner,
);

void main() {
  // A closure created inside a client method drags the client (and its
  // unsendable Dio adapter) into Isolate.run, which then throws. Every list
  // endpoint must go through the top-level helpers.
  group('real isolate runner, unsendable adapter, bodies over 64 KB', () {
    Map<String, Object?> movie(int i) => {
      'id': i,
      'title': 'Example Movie $i ${'x' * 60}',
      'tmdbId': i,
    };

    test('movies', () async {
      final r = await _client(_big(movie)).movies();
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull?.length, 1200);
    });

    test('calendar', () async {
      final r = await _client(
        _big(movie),
      ).calendar(DateTime.utc(2026), DateTime.utc(2026, 2));
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull?.length, 1200);
    });

    test('queue', () async {
      final r = await _client(
        _big(
          (i) => {
            'id': i,
            'movieId': i,
            'title': 'Example.Movie.${'x' * 60}.$i',
            'size': 100,
            'sizeleft': 50,
          },
          paged: true,
        ),
      ).queue();
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull?.length, 1200);
    });

    test('releases', () async {
      final r = await _client(
        _big(
          (i) => {
            'guid': 'guid-$i',
            'indexerId': 1,
            'title': 'Example.Movie.${'x' * 60}.$i',
          },
        ),
      ).releases(1);
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull?.length, 1200);
    });

    test('lookup', () async {
      final r = await _client(_big(movie)).lookup('example');
      expect(r.errorOrNull, isNull);
      expect(r.valueOrNull?.length, 1200);
    });

    test('quality profiles, tags and root folders', () async {
      final profiles = await _client(
        _big((i) => {'id': i, 'name': 'Profile $i ${'x' * 60}'}),
      ).qualityProfiles();
      expect(profiles.errorOrNull, isNull);
      expect(profiles.valueOrNull?.length, 1200);

      final tags = await _client(
        _big((i) => {'id': i, 'label': 'tag-$i-${'x' * 60}'}),
      ).tags();
      expect(tags.errorOrNull, isNull);
      expect(tags.valueOrNull?.length, 1200);

      final folders = await _client(
        _big((i) => {'id': i, 'path': '/media/folder-$i/${'x' * 60}'}),
      ).rootFolders();
      expect(folders.errorOrNull, isNull);
      expect(folders.valueOrNull?.length, 1200);
    });
  });
}
