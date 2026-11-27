// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:consolarr/features/servers/application/server_connection.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/home/sonarr_home_screen.dart';
import 'package:consolarr/src/cache/payload_cache.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

/// Which fake server is "active"; changing it rebuilds the connection the way
/// a real set-active does.
class _ActiveId extends Notifier<String> {
  @override
  String build() => 'a';
  void switchTo(String id) => state = id;
}

final _activeId = NotifierProvider<_ActiveId, String>(_ActiveId.new);

/// Answers per server; a server can be made to wait or to fail.
class _Servers {
  final gates = <String, Completer<void>>{};
  final failing = <String, int>{};
  final titles = {'a': 'Show From Server A', 'b': 'Show From Server B'};

  ServerConnection connection(String id) {
    final profile = ServerProfile.parse(
      id: id,
      name: id,
      kind: ServiceKind.sonarr,
      address: 'https://$id.sonarr.example',
    ).valueOrNull!;
    final dio = Dio(BaseOptions(baseUrl: profile.baseUri.toString()))
      ..httpClientAdapter = _Adapter(this, id);
    return ServerConnection(profile: profile, dio: dio);
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.servers, this.id);
  final _Servers servers;
  final String id;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await servers.gates[id]?.future;
    final status = servers.failing[id];
    if (status != null) return ResponseBody.fromString('', status);
    return ResponseBody.fromString(
      seriesJson([fakeSeries(1, title: servers.titles[id])]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late _Servers servers;

  setUp(() {
    db = AppDatabase.memory();
    servers = _Servers();
  });
  tearDown(() => db.close());

  List<Override> overrides() => [
    activeConnectionProvider.overrideWith(
      (ref, kind) async => servers.connection(ref.watch(_activeId)),
    ),
    payloadCacheProvider.overrideWithValue(DriftPayloadCache(db)),
    clockProvider.overrideWithValue(() => fixedNow),
    viewModeStoreProvider.overrideWithValue(MemoryViewModeStore()),
    artworkSourceProvider.overrideWithValue(null),
  ];

  group('provider transitions', () {
    test('a switch reloads: loading, then the new server only', () async {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: overrides(),
      );
      addTearDown(c.dispose);
      final sub = c.listen(seriesLibraryProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await c.read(seriesLibraryProvider.future) as LibraryData;
      expect(first.snapshot.series.single.title, 'Show From Server A');

      servers.gates['b'] = Completer<void>();
      c.read(_activeId.notifier).switchTo('b');
      await pumpEventQueue();
      final during = c.read(seriesLibraryProvider);
      expect(during.isLoading, isTrue);

      servers.gates['b']!.complete();
      final second = await c.read(seriesLibraryProvider.future) as LibraryData;
      expect(second.snapshot.series.single.title, 'Show From Server B');
    });

    test('a refresh that finishes after a switch is dropped', () async {
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: overrides(),
      );
      addTearDown(c.dispose);
      final sub = c.listen(seriesLibraryProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(seriesLibraryProvider.future);

      servers.gates['a'] = Completer<void>();
      final refreshing = c.read(seriesLibraryProvider.notifier).refresh();
      await pumpEventQueue();

      servers.titles['b'] = 'Show From Server B';
      c.read(_activeId.notifier).switchTo('b');
      final settled = await c.read(seriesLibraryProvider.future) as LibraryData;
      expect(settled.snapshot.series.single.title, 'Show From Server B');

      servers.gates['a']!.complete();
      await refreshing;
      await pumpEventQueue();
      final after = c.read(seriesLibraryProvider).value! as LibraryData;
      expect(
        after.snapshot.series.single.title,
        'Show From Server B',
        reason: 'the late answer of server A must not overwrite server B',
      );
    });
  });

  group('screen after a switch', () {
    testWidgets('shows a skeleton, not the previous server, while loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides(),
          child: _screen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Show From Server A'), findsWidgets);

      servers.gates['b'] = Completer<void>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      container.read(_activeId.notifier).switchTo('b');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Show From Server A'), findsNothing);
      expect(find.textContaining('Show From Server B'), findsNothing);

      servers.gates['b']!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Show From Server B'), findsWidgets);
    });

    testWidgets('shows the error, not the previous server, when the new one '
        'fails', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides(),
          child: _screen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Show From Server A'), findsWidgets);

      servers.failing['b'] = 401;
      ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
          .read(_activeId.notifier)
          .switchTo('b');
      await tester.pumpAndSettle();
      expect(find.textContaining('Show From Server A'), findsNothing);
    });
  });
}

Widget _screen() => harnessApp(
  const HarnessVariant(
    size: Size(360, 800),
    textScale: 1,
    locale: Locale('en'),
    brightness: Brightness.dark,
  ),
  const ConsolarrEffectsScope(
    reduceMotion: true,
    child: Scaffold(body: SonarrHomeScreen()),
  ),
);
