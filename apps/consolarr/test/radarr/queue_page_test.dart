// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/queue_page.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

const _pad = EdgeInsets.fromLTRB(16, 60, 16, 88);
final _both = [...phone, ...stress];

bool _en(HarnessVariant v) => v.locale == const Locale('en');

Widget _page(HarnessVariant v, FakeRadarrApi api) =>
    radarrApp(v, api, const QueuePage(padding: _pad, active: false));

FakeRadarrApi _api(List<ArrQueueItem> items) => FakeRadarrApi(
  moviesResult: Result.ok([fakeMovie(7, title: 'Library Title')]),
)..queueResult = Result.ok(items);

List<ArrQueueItem> _items() => [
  fakeQueueItem(
    1,
    movieId: 7,
    title: 'Example.Movie.2024.1080p',
    size: 1000,
    sizeLeft: 400,
    messages: const [
      ArrStatusMessage(messages: ['No files found are eligible for import']),
    ],
  ),
  fakeQueueItem(
    2,
    title: 'Unknown.Movie.Release',
    state: ArrQueueState.paused,
    size: 10,
  ),
  fakeQueueItem(
    3,
    title: 'Ignored.Release',
    state: ArrQueueState.ignored,
    size: 10,
  ),
  fakeQueueItem(
    4,
    title: 'Broken.Release',
    state: ArrQueueState.importFailed,
    size: 10,
  ),
];

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(QueuePage)));

void main() {
  group('queue rows (RAD-11)', () {
    testWidgets('use the shared row, status text and the movie title', (
      tester,
    ) async {
      await pumpMatrix(
        tester,
        (v) => _page(v, _api(_items())),
        variants: _both,
        verify: (v) async {
          if (_en(v)) {
            // The library title for a known movie, the release name for an
            // item without one.
            expect(find.text('Library Title'), findsOneWidget);
            expect(find.text('Unknown.Movie.Release'), findsOneWidget);
            expect(find.text('Downloading'), findsOneWidget);
            expect(find.text('Paused'), findsOneWidget);
            expect(find.text('Ignored'), findsOneWidget);
          }
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('server messages expand as plain text', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _page(v, _api(_items())),
        variants: phone,
      );
      expect(find.text('No files found are eligible for import'), findsNothing);
      await tester.tap(find.byIcon(Icons.warning_amber).first);
      await tester.pumpAndSettle();
      expect(find.text('No files found are eligible for import'), findsOne);
      // No hand-made bullet in front of the text.
      expect(find.textContaining('•'), findsNothing);
    });

    testWidgets('empty queue, and every error', (tester) async {
      await pumpMatrix(
        tester,
        (v) => _page(v, FakeRadarrApi()),
        variants: _both,
        verify: (v) async {
          if (_en(v)) {
            expect(find.text('Nothing is downloading'), findsOneWidget);
          }
          await expectAccessible(tester);
        },
      );
    });

    for (final c in ErrorCategory.values) {
      testWidgets('error ${c.code}', (tester) async {
        final api = FakeRadarrApi()..queueResult = Result.err(AppError(c));
        await pumpMatrix(
          tester,
          (v) => _page(v, api),
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      });
    }
  });

  group('offline queue', () {
    testWidgets('shows the banner and disables removing', (tester) async {
      final api = _api(_items());
      await pumpMatrix(
        tester,
        (v) => _page(v, api),
        variants: phone,
        verify: (v) async {},
      );
      api.queueResult = const Result.err(AppError(ErrorCategory.timeout));
      await _container(tester).read(queueProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBanner), findsOneWidget);
      final buttons = tester.widgetList<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(buttons, isNotEmpty);
      for (final b in buttons) {
        expect(b.onPressed, isNull);
        // The disabled button says why.
        expect(
          b.tooltip,
          'Changes are disabled while the server is unreachable.',
        );
      }
      // The rows themselves are still readable.
      expect(find.text('Library Title'), findsOneWidget);
      api.calls.clear();
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline).first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.text('Remove from queue?'), findsNothing);
    });

    testWidgets('is accessible in every variant, with the banner', (
      tester,
    ) async {
      final api = _api(_items());
      await pumpMatrix(
        tester,
        (v) => _page(v, api),
        variants: _both,
        verify: (v) async {
          api.queueResult = const Result.err(
            AppError(ErrorCategory.networkUnreachable),
          );
          await _container(tester).read(queueProvider.notifier).refresh();
          await tester.pumpAndSettle();
          expect(find.byType(OfflineBanner), findsOneWidget);
          await expectAccessible(tester);
          api.queueResult = Result.ok(_items());
        },
      );
    });

    testWidgets('an empty cached queue still shows the banner', (tester) async {
      final api = _api(const []);
      await pumpMatrix(
        tester,
        (v) => _page(v, api),
        variants: phone,
        verify: (v) async {},
      );
      // Nothing cached to fall back to: an error, not a banner.
      api.queueResult = const Result.err(AppError(ErrorCategory.timeout));
      await _container(tester).read(queueProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.byType(OfflineBanner), findsOneWidget);
    });
  });

  group('removal', () {
    testWidgets('asks, states the consequence and sends the choice', (
      tester,
    ) async {
      final api = _api(_items());
      await pumpMatrix(tester, (v) => _page(v, api), variants: phone);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Remove from queue?'), findsOneWidget);
      expect(find.text('Library Title'), findsWidgets);
      expect(
        find.textContaining('deleted from the download client'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(api.calls.single, startsWith('remove 1 client=true'));
      expect(find.text('Removed from the queue'), findsOneWidget);
      expect(find.text('Example.Movie.2024.1080p'), findsNothing);
    });

    testWidgets('a failure keeps the row and offers a retry', (tester) async {
      final api = _api(_items())
        ..removeResult = const Result.err(AppError(ErrorCategory.serverError));
      await pumpMatrix(tester, (v) => _page(v, api), variants: phone);
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't remove the item"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('the dialog is accessible in the stress variants', (
      tester,
    ) async {
      final api = _api(_items());
      await pumpMatrix(
        tester,
        (v) => _page(v, api),
        variants: _both,
        verify: (v) async {
          await tester.tap(find.byIcon(Icons.delete_outline).first);
          await tester.pumpAndSettle();
          await expectAccessible(tester);
          await tester.tap(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(TextButton),
                )
                .first,
          );
          await tester.pumpAndSettle();
        },
      );
    });
  });
}
