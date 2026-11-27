// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftPayloadCache cache;

  setUp(() {
    db = AppDatabase.memory();
    cache = DriftPayloadCache(db);
  });
  tearDown(() => db.close());

  test('returns null when nothing is cached', () async {
    expect(await cache.read('s1', 'sonarr.series'), isNull);
  });

  test('round-trips a payload with its fetch time', () async {
    final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
    await cache.write('s1', 'sonarr.series', '[1,2]', at);
    final hit = await cache.read('s1', 'sonarr.series');
    expect(hit!.json, '[1,2]');
    expect(hit.fetchedAt.toUtc(), at);
  });

  test('write replaces; entries are per server and key', () async {
    final at = DateTime.utc(2026);
    await cache.write('s1', 'k', 'a', at);
    await cache.write('s1', 'k', 'b', at);
    await cache.write('s2', 'k', 'c', at);
    expect((await cache.read('s1', 'k'))!.json, 'b');
    expect((await cache.read('s2', 'k'))!.json, 'c');
  });

  test('deleteForServer removes only that server', () async {
    final at = DateTime.utc(2026);
    await cache.write('s1', 'k', 'a', at);
    await cache.write('s2', 'k', 'c', at);
    await cache.deleteForServer('s1');
    expect(await cache.read('s1', 'k'), isNull);
    expect(await cache.read('s2', 'k'), isNotNull);
  });
}
