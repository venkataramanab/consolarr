// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/radarr/application/radarr_providers.dart';
import 'package:consolarr/features/radarr/presentation/release_sheet.dart';
import 'package:consolarr/features/arr_common/presentation/release_row.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'harness.dart';
import 'support.dart';

bool _en(HarnessVariant v) => v.locale == const Locale('en');

final _both = [...phone, ...stress];

final _releases = [
  fakeRelease(
    'a',
    title: 'Example.Movie.2024.1080p.WEB',
    seeders: 40,
    ageMinutes: 300,
  ),
  fakeRelease(
    'b',
    title: 'Example.Movie.2024.720p.CAM',
    size: 1 << 30,
    ageMinutes: 6000,
    seeders: 2,
    protocol: ArrProtocol.usenet,
    resolution: 720,
    approved: false,
    rejections: ['Quality is not wanted', 'Not an upgrade'],
  ),
];

Future<void> _pumpSheet(
  WidgetTester tester,
  FakeRadarrApi api, {
  List<HarnessVariant>? variants,
  Future<void> Function(HarnessVariant)? verify,
}) => pumpMatrix(
  tester,
  (v) => radarrApp(v, api, const ReleaseSheetBody(movieId: 7)),
  variants: variants ?? phone,
  verify: verify,
);

const _timeout = Result<void>.err(AppError(ErrorCategory.timeout));

List<String> _grabs(FakeRadarrApi api) =>
    api.calls.where((c) => c.startsWith('grab')).toList();

class _Server extends Notifier<String> {
  @override
  String build() => 'srv1';
  void set(String v) => state = v;
}

void main() {
  group('release sheet (RAD-13)', () {
    testWidgets('lists, sorts, filters', (tester) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(_releases);
      await _pumpSheet(
        tester,
        api,
        variants: _both,
        verify: (v) => expectAccessible(tester),
      );
      await _pumpSheet(tester, api);
      expect(find.text('Example.Movie.2024.1080p.WEB'), findsOneWidget);
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Rejected'));
      await tester.pumpAndSettle();
      expect(find.text('Example.Movie.2024.1080p.WEB'), findsNothing);
      expect(find.text('Example.Movie.2024.720p.CAM'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Rejected'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Accepted'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '720p'));
      await tester.pumpAndSettle();
      expect(find.text('No release matches'), findsOneWidget);
    });

    testWidgets('none found', (tester) async {
      await _pumpSheet(
        tester,
        FakeRadarrApi(),
        variants: _both,
        verify: (v) async {
          if (_en(v)) expect(find.text('No releases found'), findsOneWidget);
          await expectAccessible(tester);
        },
      );
    });

    for (final c in ErrorCategory.values) {
      testWidgets('error ${c.code}', (tester) async {
        final api = FakeRadarrApi()..releasesResult = Result.err(AppError(c));
        await _pumpSheet(
          tester,
          api,
          variants: stress,
          verify: (v) => expectAccessible(tester),
        );
      });
    }

    testWidgets('long release names stay readable (ar / en_XA, 2.0, 320)', (
      tester,
    ) async {
      final long = 'Example.Movie.${'x' * 160}.2024.1080p.WEB-DL-GROUP';
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok([
          fakeRelease('a', title: long, indexer: 'Indexer ${'y' * 80}'),
          fakeRelease(
            'b',
            title: 'فيلم مثال ${'طويل ' * 40}',
            approved: false,
            rejections: ['سبب ${'طويل ' * 30}'],
          ),
        ]);
      await _pumpSheet(
        tester,
        api,
        variants: stress,
        verify: (v) async {
          expect(tester.takeException(), isNull);
          await expectAccessible(tester);
        },
      );
    });

    testWidgets('the sheet opens as a full glass sheet with a lazy list', (
      tester,
    ) async {
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok([
          for (var i = 0; i < 400; i++) fakeRelease('g$i', title: 'Rel $i'),
        ]);
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showReleaseSheet(context, 7),
              child: const Text('open'),
            ),
          ),
        ),
        variants: phone,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassSheet), findsOneWidget);
      // 400 rows, but only the visible ones are built.
      expect(find.byType(ReleaseRow), findsAtLeastNWidgets(1));
      expect(find.byType(ReleaseRow).evaluate().length, lessThan(60));
    });
  });

  group('grab (M1)', () {
    testWidgets('an accepted release is sent directly, once', (tester) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(_releases);
      await _pumpSheet(tester, api);
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(_grabs(api), ['grab a']);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('a rejected release needs a confirm that shows the reasons', (
      tester,
    ) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(_releases);
      await _pumpSheet(tester, api);
      await tester.tap(find.text('Download').last);
      await tester.pumpAndSettle();
      expect(find.text('Download a rejected release?'), findsOneWidget);
      expect(find.textContaining('Not an upgrade'), findsOneWidget);
      expect(_grabs(api), isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_grabs(api), isEmpty);
      await tester.tap(find.text('Download').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download anyway'));
      await tester.pumpAndSettle();
      expect(_grabs(api), ['grab b']);
    });

    testWidgets('a 4xx failure is a plain failure with a retry', (
      tester,
    ) async {
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok(_releases)
        ..grabResult = const Result.err(AppError(ErrorCategory.authFailed));
      await _pumpSheet(tester, api);
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not send this release to the download client.'),
        findsOneWidget,
      );
      expect(find.text('May have been sent'), findsNothing);
      api.grabResult = const Result.ok(null);
      await tester.tap(find.text('Check and send again').first);
      await tester.pumpAndSettle();
      expect(_grabs(api), ['grab a', 'grab a']);
    });

    testWidgets('a timeout is "maybe sent"; the queue has it: no second POST', (
      tester,
    ) async {
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok(_releases)
        ..grabResult = _timeout;
      await _pumpSheet(tester, api);
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(find.text('May have been sent'), findsOneWidget);
      // Nothing retries by itself.
      await tester.pump(const Duration(minutes: 5));
      expect(_grabs(api), ['grab a']);

      api.queueResult = Result.ok([
        fakeQueueItem(1, title: 'Example.Movie.2024.1080p.WEB'),
      ]);
      await tester.tap(find.text('Check and send again').first);
      await tester.pumpAndSettle();
      expect(_grabs(api), ['grab a']);
      expect(find.text('Sent'), findsOneWidget);
      expect(
        find.text('This release is already in the queue.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'queue lacks it: confirm; cancel sends nothing, ok sends once',
      (tester) async {
        final api = FakeRadarrApi()
          ..releasesResult = Result.ok(_releases)
          ..grabResult = _timeout;
        await _pumpSheet(tester, api);
        await tester.tap(find.text('Download').first);
        await tester.pumpAndSettle();
        api.grabResult = const Result.ok(null);

        await tester.tap(find.text('Check and send again').first);
        await tester.pumpAndSettle();
        expect(find.text('Send this release again?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(_grabs(api), ['grab a']);

        await tester.tap(find.text('Check and send again').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send again'));
        await tester.pumpAndSettle();
        expect(_grabs(api), ['grab a', 'grab a']);
        expect(find.text('Sent'), findsOneWidget);
      },
    );

    testWidgets('an unreadable queue still asks before sending again', (
      tester,
    ) async {
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok(_releases)
        ..grabResult = _timeout
        ..queueResult = const Result.err(AppError(ErrorCategory.timeout));
      await _pumpSheet(tester, api);
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check and send again').first);
      await tester.pumpAndSettle();
      expect(find.text('Send this release again?'), findsOneWidget);
      expect(_grabs(api), ['grab a']);
    });

    testWidgets('reopening: what was sent or queued is not offered again', (
      tester,
    ) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(_releases);
      late WidgetRef outer;
      await pumpMatrix(
        tester,
        (v) => radarrApp(
          v,
          api,
          Consumer(
            builder: (context, ref, _) {
              outer = ref;
              return FilledButton(
                onPressed: () => showReleaseSheet(context, 7),
                child: const Text('open'),
              );
            },
          ),
        ),
        variants: phone,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(find.text('Sent'), findsOneWidget);
      expect(outer.read(grabStatusProvider), isNotEmpty);

      // Close and reopen: the first release still reads "Sent".
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(_grabs(api), ['grab a']);
    });

    testWidgets('reopening: a release found in the queue is marked sent', (
      tester,
    ) async {
      final api = FakeRadarrApi()
        ..releasesResult = Result.ok(_releases)
        ..queueResult = Result.ok([
          fakeQueueItem(1, title: 'Example.Movie.2024.1080p.WEB', movieId: 7),
        ]);
      await _pumpSheet(tester, api);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    test('the grab state does not leak to another server', () async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(_releases);
      final server = NotifierProvider<_Server, String>(_Server.new);
      final container = ProviderContainer(
        overrides: [
          ...radarrOverrides(api, includeContext: false),
          radarrContextProvider.overrideWith(
            (ref) async => RadarrContext(
              api: api,
              repository: contextFor(api).repository,
              serverId: ref.watch(server),
              dio: Dio(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(grabStatusProvider, (_, _) {});
      await container.read(radarrContextProvider.future);
      await container.read(grabStatusProvider.notifier).grab(_releases.first);
      expect(container.read(grabStatusProvider), isNotEmpty);
      container.read(server.notifier).set('srv2');
      await container.read(radarrContextProvider.future);
      expect(container.read(grabStatusProvider), isEmpty);
    });

    testWidgets('expanding shows rejection reasons', (tester) async {
      final api = FakeRadarrApi()..releasesResult = Result.ok(_releases);
      await _pumpSheet(tester, api);
      await tester.tap(find.byTooltip('Details').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Quality is not wanted'), findsOneWidget);
    });
  });
}
