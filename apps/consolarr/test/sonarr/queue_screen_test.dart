// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/queue_providers.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/presentation/queue/queue_body.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';

const _en = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

final _stress = harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  textScales: const [1, 2],
  locales: const [Locale('en'), Locale('ar'), Locale('en', 'XA')],
  brightnesses: const [Brightness.dark],
);

class _Events implements Analytics {
  final List<(String, Map<String, Object>)> logged = [];
  @override
  Future<void> setEnabled({required bool enabled}) async {}
  @override
  Future<void> logEvent(
    String name, {
    Map<String, Object> parameters = const {},
  }) async => logged.add((name, parameters));
}

Widget _app(
  HarnessVariant v,
  ScriptedSonarrApi api, {
  List<Override> extra = const [],
  VoidCallback? onOpenServers,
}) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ...sonarrTestOverrides(api),
      queuePollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ...extra,
    ],
    child: harnessApp(
      v,
      ConsolarrEffectsScope(
        reduceMotion: true,
        child: Scaffold(
          body: QueueBody(
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 88),
            onOpenServers: onOpenServers,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  ScriptedSonarrApi api, {
  HarnessVariant variant = _en,
  List<Override> extra = const [],
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(_app(variant, api, extra: extra));
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

void main() {
  group('states', () {
    testWidgets('loading shows a skeleton with an accessible label', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = ScriptedSonarrApi()
        ..hook = (name) => name == 'queue' ? gate.future : Future.value();
      applyVariantView(tester, _en);
      await tester.pumpWidget(_app(_en, api));
      await tester.pump();
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.bySemanticsLabel('Loading queue'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('data: rows with state, progress and details', (tester) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          fakeQueueItem(1),
          fakeQueueItem(2, state: ArrQueueState.paused, progress: 0.25),
          fakeQueueItem(3, state: ArrQueueState.importFailed),
        ]);
      await _pump(tester, api);
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Import failed'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.textContaining('12 min left'), findsWidgets);
      expect(find.textContaining('S1E1 · Example Episode 1'), findsOneWidget);
    });

    testWidgets('empty queue', (tester) async {
      await _pump(tester, ScriptedSonarrApi());
      expect(find.text('The queue is empty'), findsOneWidget);
    });

    testWidgets('no server', (tester) async {
      var opened = 0;
      applyVariantView(tester, _en);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [sonarrSessionProvider.overrideWith((ref) async => null)],
          child: harnessApp(
            _en,
            Scaffold(
              body: QueueBody(
                padding: const EdgeInsets.all(16),
                onOpenServers: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No Sonarr server'), findsOneWidget);
      await tester.tap(find.text('Add a server'));
      expect(opened, 1);
      await tester.pumpWidget(const SizedBox());
    });

    for (final entry in {
      ErrorCategory.authFailed: 'rejected',
      ErrorCategory.networkUnreachable: 'reach',
      ErrorCategory.serverError: 'error',
      ErrorCategory.unsupportedVersion: 'version',
    }.entries) {
      testWidgets('error ${entry.key.code} offers retry', (tester) async {
        final api = ScriptedSonarrApi()
          ..queueResult = Result.err(AppError(entry.key));
        await _pump(tester, api);
        expect(find.text("Couldn't load the queue"), findsOneWidget);
        expect(find.textContaining(entry.value), findsWidgets);
        api.queueResult = Result.ok([fakeQueueItem(1)]);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Downloading'), findsOneWidget);
      });
    }

    testWidgets('offline: banner, age, list kept, remove disabled+explained', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      await _pump(tester, api);
      api.queueResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
      await ProviderScope.containerOf(tester.element(find.byType(QueueBody)))
          .read(queueProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining("Can't reach Sonarr"), findsOneWidget);
      expect(find.textContaining('Updated'), findsOneWidget);
      expect(find.text('Downloading'), findsOneWidget);
      final remove = tester.widget<IconButton>(
        find.byIcon(Icons.delete_outline).hitTestable().first.evaluate().isEmpty
            ? find.byType(IconButton).last
            : find.ancestor(
                of: find.byIcon(Icons.delete_outline),
                matching: find.byType(IconButton),
              ),
      );
      expect(remove.onPressed, isNull);
      expect(remove.tooltip, 'Removing needs a connection to Sonarr');
    });

    testWidgets('warnings expand as plain text', (tester) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          fakeQueueItem(
            1,
            state: ArrQueueState.warning,
            messages: const [
              ArrStatusMessage(title: 'Example.Show', messages: ['No files']),
            ],
          ),
        ]);
      await _pump(tester, api);
      await tester.tap(find.text('1 message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No files'), findsOneWidget);
    });
  });

  group('removal flow', () {
    for (final entry in {
      "Don't blocklist": ArrBlocklistChoice.none,
      'Blocklist and search again': ArrBlocklistChoice.blocklistAndSearch,
      'Blocklist only': ArrBlocklistChoice.blocklistOnly,
    }.entries) {
      testWidgets('"${entry.key}" removes the item and reports the event', (
        tester,
      ) async {
        final events = _Events();
        final api = ScriptedSonarrApi()
          ..queueResult = Result.ok([fakeQueueItem(1), fakeQueueItem(2)]);
        await _pump(
          tester,
          api,
          extra: [analyticsProvider.overrideWithValue(events)],
        );
        api.queueResult = Result.ok([fakeQueueItem(2)]);
        await tester.tap(find.byTooltip('Remove from queue').first);
        await tester.pumpAndSettle();
        expect(find.text('Remove from queue?'), findsOneWidget);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(api.sent.last, (1, true, entry.value));
        expect(find.text('Removed from the queue'), findsOneWidget);
        expect(find.byTooltip('Remove from queue'), findsOneWidget);
        final removed = events.logged.singleWhere(
          (e) => e.$1 == 'queue_item_removed',
        );
        expect(removed.$2['from_client'], isTrue);
        // Closed values only: no titles in the event.
        expect(removed.$2.toString(), isNot(contains('Example')));
      });
    }

    testWidgets('a failed removal keeps the dialog with retry', (tester) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      await _pump(tester, api);
      api.removeResult = const Result.err(AppError(ErrorCategory.timeout));
      await tester.tap(find.byTooltip('Remove from queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't remove the item"), findsOneWidget);
      api.removeResult = const Result.ok(null);
      api.queueResult = const Result.ok([]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from queue?'), findsNothing);
      expect(api.count('removeQueueItem'), 2);
    });
  });

  group('provider transition (real providers)', () {
    testWidgets('a server switch shows loading, then only the new queue', (
      tester,
    ) async {
      final a = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          ArrQueueItem(id: 1, title: 'x', mediaTitle: 'Show From Server A'),
        ]);
      final b = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          ArrQueueItem(id: 1, title: 'x', mediaTitle: 'Show From Server B'),
        ]);
      final gate = Completer<void>();
      b.hook = (name) => name == 'queue' ? gate.future : Future.value();
      final active = NotifierProvider<_Active, String>(_Active.new);
      final overrides = [
        sonarrSessionProvider.overrideWith(
          (ref) async => SonarrSession(
            api: ref.watch(active) == 'a' ? a : b,
            serverId: ref.watch(active),
            cache: MemoryPayloadCache(),
            clock: () => DateTime.utc(2026, 5, 1),
          ),
        ),
        queuePollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ];
      applyVariantView(tester, _en);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides,
          child: harnessApp(
            _en,
            Scaffold(body: QueueBody(padding: const EdgeInsets.all(16))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show From Server A'), findsOneWidget);

      ProviderScope.containerOf(tester.element(find.byType(QueueBody)))
              .read(active.notifier)
              .state =
          'b';
      await tester.pump();
      await tester.pump();
      expect(find.text('Show From Server A'), findsNothing);
      expect(find.byType(SkeletonBox), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Show From Server B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a switch to a failing server shows the error', (tester) async {
      final a = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          ArrQueueItem(id: 1, title: 'x', mediaTitle: 'Show From Server A'),
        ]);
      final b = ScriptedSonarrApi()
        ..queueResult = const Result.err(AppError(ErrorCategory.authFailed));
      final active = NotifierProvider<_Active, String>(_Active.new);
      applyVariantView(tester, _en);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sonarrSessionProvider.overrideWith(
              (ref) async => SonarrSession(
                api: ref.watch(active) == 'a' ? a : b,
                serverId: ref.watch(active),
                cache: MemoryPayloadCache(),
                clock: () => DateTime.utc(2026, 5, 1),
              ),
            ),
            queuePollIntervalProvider.overrideWithValue(
              const Duration(hours: 1),
            ),
          ],
          child: harnessApp(
            _en,
            Scaffold(body: QueueBody(padding: const EdgeInsets.all(16))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ProviderScope.containerOf(tester.element(find.byType(QueueBody)))
              .read(active.notifier)
              .state =
          'b';
      await tester.pumpAndSettle();
      expect(find.text('Show From Server A'), findsNothing);
      expect(find.text("Couldn't load the queue"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('extremes and layout', () {
    testWidgets('10,000 items build lazily', (tester) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          for (var i = 1; i <= 10000; i++) fakeQueueItem(i),
        ]);
      await _pump(tester, api);
      expect(find.byType(Scrollable).evaluate().isNotEmpty, isTrue);
      // Only the visible rows exist.
      expect(
        find.byTooltip('Remove from queue').evaluate().length,
        lessThan(20),
      );
    });

    testWidgets('states in the stress matrix: no overflow, accessible', (
      tester,
    ) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          fakeQueueItem(1),
          fakeQueueItem(
            2,
            state: ArrQueueState.warning,
            messages: [
              ArrStatusMessage(
                title: 'T ${'long ' * 20}',
                messages: ['M ${'x ' * 30}'],
              ),
            ],
          ),
          fakeQueueItem(3, state: ArrQueueState.clientUnavailable),
        ]);
      await pumpMatrix(
        tester,
        (v) => _app(v, api),
        variants: _stress,
        verify: (v) => expectAccessible(tester),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('empty and error states in the matrix', (tester) async {
      for (final api in [
        ScriptedSonarrApi(),
        ScriptedSonarrApi()
          ..queueResult = const Result.err(AppError(ErrorCategory.timeout)),
      ]) {
        await pumpMatrix(
          tester,
          (v) => _app(v, api),
          variants: harnessMatrix(
            sizes: const [Size(320, 568)],
            textScales: const [2],
            locales: const [Locale('ar'), Locale('en', 'XA')],
          ),
          verify: (v) => expectAccessible(tester),
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('goldens', () {
    testWidgets('data (en, dark, 360x800)', (tester) async {
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([
          fakeQueueItem(1),
          fakeQueueItem(2, state: ArrQueueState.paused, progress: 0.25),
          fakeQueueItem(
            3,
            state: ArrQueueState.importFailed,
            progress: 1,
            messages: const [
              ArrStatusMessage(messages: ['No eligible files found']),
            ],
          ),
          fakeQueueItem(4, state: ArrQueueState.queued, progress: 0),
        ]);
      await _pump(tester, api);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/queue_data_en_dark_360x800.png'),
      );
    });

    testWidgets('offline (ar, light, 360x800)', (tester) async {
      const v = HarnessVariant(
        size: Size(360, 800),
        textScale: 1,
        locale: Locale('ar'),
        brightness: Brightness.light,
      );
      final api = ScriptedSonarrApi()
        ..queueResult = Result.ok([fakeQueueItem(1)]);
      await _pump(tester, api, variant: v);
      api.queueResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
      await ProviderScope.containerOf(tester.element(find.byType(QueueBody)))
          .read(queueProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/queue_offline_ar_light_360x800.png'),
      );
    });

    testWidgets('empty (en_XA, dark, 320x568)', (tester) async {
      const v = HarnessVariant(
        size: Size(320, 568),
        textScale: 1,
        locale: Locale('en', 'XA'),
        brightness: Brightness.dark,
      );
      await _pump(tester, ScriptedSonarrApi(), variant: v);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/queue_empty_xa_dark_320x568.png'),
      );
    });
  });
}

class _Active extends Notifier<String> {
  @override
  String build() => 'a';
}
