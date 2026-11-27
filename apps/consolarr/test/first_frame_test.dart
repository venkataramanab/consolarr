// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/images/image_cache_config.dart';
import 'package:security/security.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

/// Records which providers are created before `firstFrameDoneProvider` flips.
base class _EarlyReads extends ProviderObserver {
  bool firstFrameDone = false;
  final List<String> early = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    if (!firstFrameDone)
      early.add(context.provider.name ?? '${context.provider.runtimeType}');
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (context.provider == firstFrameDoneProvider && newValue == true) {
      firstFrameDone = true;
    }
  }
}

void main() {
  testWidgets('the database and shell providers are not read before the '
      'first frame', (tester) async {
    final reads = _EarlyReads();
    await tester.pumpWidget(
      ProviderScope(
        observers: [reads],
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.memory();
            ref.onDispose(db.close);
            return db;
          }),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        ],
        child: const ConsolarrApp(),
      ),
    );
    // pumpWidget ran the first frame and its post-frame callback.
    expect(reads.firstFrameDone, isTrue);
    const forbidden = {
      'databaseProvider',
      'serverRepositoryProvider',
      'serversProvider',
      'payloadCacheProvider',
      'pinStoreProvider',
      'secureHttpClientFactoryProvider',
      'activeConnectionProvider',
      'activeConnectionKeyProvider',
    };
    final touched = reads.early.where(forbidden.contains).toList();
    expect(
      touched,
      isEmpty,
      reason: 'providers created before the first frame: $touched',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('the image cache is capped after the first frame, not before', (
    tester,
  ) async {
    final cache = PaintingBinding.instance.imageCache;
    final before = cache.maximumSizeBytes;
    cache.maximumSizeBytes = 100 * 1024 * 1024;
    addTearDown(() {
      cache
        ..maximumSizeBytes = before
        ..maximumSize = 1000;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.memory();
            ref.onDispose(db.close);
            return db;
          }),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        ],
        child: const ConsolarrApp(),
      ),
    );
    expect(cache.maximumSizeBytes, imageCacheMaxBytes);
    expect(imageCacheMaxBytes, closeTo(50 * 1024 * 1024, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('no network or database access before the first frame', (
    tester,
  ) async {
    await expectNoIoBeforeFirstFrame(
      tester,
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.memory();
            ref.onDispose(db.close);
            return db;
          }),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        ],
        child: const ConsolarrApp(),
      ),
    );
    // And the first frame really was produced.
    expect(find.byType(ConsolarrApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
