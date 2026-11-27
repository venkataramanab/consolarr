// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/data/view_mode_store.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

class _MemoryViewModeStore implements ViewModeStore {
  LibraryViewMode? stored;
  @override
  Future<LibraryViewMode?> read() async => stored;
  @override
  Future<void> write(LibraryViewMode mode) async => stored = mode;
}

void main() {
  late AppDatabase db;

  ProviderContainer container({
    required Future<ServerConnection?> Function() connection,
    ViewModeStore? viewModes,
  }) {
    final c = ProviderContainer(
      // Typed failures are results, not transient errors: never retry them.
      retry: (_, _) => null,
      overrides: [
        activeConnectionProvider.overrideWith((ref, kind) => connection()),
        payloadCacheProvider.overrideWithValue(DriftPayloadCache(db)),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 5, 1)),
        viewModeStoreProvider.overrideWithValue(
          viewModes ?? _MemoryViewModeStore(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('no server configured', () async {
    final c = container(connection: () async => null);
    expect(await c.read(seriesLibraryProvider.future), isA<LibraryNoServer>());
  });

  test('missing credentials surface as a failure, never a throw', () async {
    final c = container(
      connection: () async => throw const AppError(
        ErrorCategory.authFailed,
        debugDetail: 'needs_credentials',
      ),
    );
    final s = await c.read(seriesLibraryProvider.future);
    expect(s, isA<LibraryFailure>());
    expect((s as LibraryFailure).error.debugDetail, 'needs_credentials');
  });

  test('loads series through the connection Dio', () async {
    final c = container(
      connection: () async =>
          fakeConnection(jsonAdapter(seriesJson(fakeSeriesList(3)))),
    );
    final s = await c.read(seriesLibraryProvider.future) as LibraryData;
    expect(s.snapshot.series, hasLength(3));
    expect(s.isOffline, isFalse);
    expect(s.isEmpty, isFalse);
  });

  test('an empty library is data with isEmpty', () async {
    final c = container(
      connection: () async => fakeConnection(jsonAdapter('[]')),
    );
    final s = await c.read(seriesLibraryProvider.future) as LibraryData;
    expect(s.isEmpty, isTrue);
  });

  test('auth failure with no cache is a failure', () async {
    final c = container(
      connection: () async =>
          fakeConnection(StubAdapter((_) => ResponseBody.fromString('', 401))),
    );
    final s = await c.read(seriesLibraryProvider.future) as LibraryFailure;
    expect(s.error.category, ErrorCategory.authFailed);
  });

  test('refresh failure keeps the content and marks it offline', () async {
    var fail = false;
    final c = container(
      connection: () async => fakeConnection(
        StubAdapter(
          (_) => fail
              ? ResponseBody.fromString('', 503)
              : ResponseBody.fromString(
                  seriesJson(fakeSeriesList(2)),
                  200,
                  headers: {
                    Headers.contentTypeHeader: [Headers.jsonContentType],
                  },
                ),
        ),
      ),
    );
    await c.read(seriesLibraryProvider.future);
    fail = true;
    await c.read(seriesLibraryProvider.notifier).refresh();
    final s = c.read(seriesLibraryProvider).value! as LibraryData;
    expect(s.snapshot.series, hasLength(2));
    expect(s.isOffline, isTrue);
    expect(s.snapshot.offlineError?.category, ErrorCategory.serverError);
  });

  test('view mode defaults to grid and persists', () async {
    final store = _MemoryViewModeStore();
    final c = container(connection: () async => null, viewModes: store);
    expect(c.read(viewModeProvider), LibraryViewMode.grid);
    await c.read(viewModeProvider.notifier).set(LibraryViewMode.list);
    expect(c.read(viewModeProvider), LibraryViewMode.list);
    expect(store.stored, LibraryViewMode.list);
  });

  test('a stored view mode is restored', () async {
    final store = _MemoryViewModeStore()..stored = LibraryViewMode.list;
    final c = container(connection: () async => null, viewModes: store);
    c.listen(viewModeProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(viewModeProvider), LibraryViewMode.list);
  });
}
