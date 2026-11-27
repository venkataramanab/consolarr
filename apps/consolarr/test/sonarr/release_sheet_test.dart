// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/release_search.dart';
import 'package:consolarr/features/sonarr/application/sonarr_session.dart';
import 'package:consolarr/features/sonarr/presentation/search/interactive_search_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';
import 'release_harness.dart';

void main() {
  // Stress variants only: full guideline checks are slow.
  Future<void> Function(HarnessVariant) accessible(WidgetTester tester) =>
      (v) async {
        if (v.textScale == 2.0 && v.size.width == 320) {
          await expectLabeledTapTargets(tester);
        }
      };

  testWidgets('searching shows a labelled skeleton', (tester) async {
    final api = ScriptedSonarrApi();
    final gate = Completer<void>();
    api.hook = (name) => name == 'releases' ? gate.future : Future.value();
    await tester.pumpWidget(releaseApp(releaseVariants.first, api));
    await tester.pump();
    expect(find.bySemanticsLabel('Searching for releases'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('none found offers search again', (tester) async {
    final api = ScriptedSonarrApi();
    await pumpMatrix(
      tester,
      (v) => releaseApp(v, api),
      variants: releaseVariants,
      verify: accessible(tester),
    );
    await pumpEn(tester, api);
    expect(find.text('No releases found'), findsOneWidget);
    await tester.tap(find.text('Search again'));
    await tester.pumpAndSettle();
    expect(api.count('releases'), greaterThan(1));
  });

  testWidgets('error shows cause and retry (all variants)', (tester) async {
    final api = ScriptedSonarrApi()
      ..releasesResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
    await pumpMatrix(
      tester,
      (v) => releaseApp(v, api),
      variants: releaseVariants,
      verify: accessible(tester),
    );
    await pumpEn(tester, api);
    expect(find.text("Couldn't search for releases"), findsOneWidget);
  });

  testWidgets('results list rows, expand shows rejection reasons', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([
        fakeRelease(1),
        fakeRelease(2, rejections: ['Not an upgrade', 'Size too big']),
      ]);
    await pumpMatrix(
      tester,
      (v) => releaseApp(v, api),
      variants: releaseVariants,
      verify: accessible(tester),
    );
    await pumpEn(tester, api);
    expect(find.textContaining('GRP1'), findsOneWidget);
    expect(find.text('Rejected'), findsWidgets);
    expect(find.text('Not an upgrade'), findsNothing);
    final expand = find.byTooltip('Show details');
    await tester.ensureVisible(expand.first);
    await tester.tap(expand.first);
    await tester.pumpAndSettle();
    expect(find.text('• Not an upgrade'), findsOneWidget);
    expect(find.text('Why it was rejected'), findsOneWidget);
  });

  testWidgets('filters that hide everything show the filter-empty state', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(1)]);
    await pumpEn(tester, api);
    await tester.tap(find.textContaining('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Rejected'));
    await tester.pumpAndSettle();
    expect(find.text('No releases match your filters'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Clear filters').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('GRP1'), findsOneWidget);
  });

  testWidgets('grabbing disables the button; grabbed shows confirmation', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(1)])
      ..hook = (n) => n == 'grabRelease' ? gate.future : Future.value();
    await pumpEn(tester, api);
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(find.text('Sending to download client…'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sent to download client'), findsOneWidget);
    expect(api.count('grabRelease'), 1);
  });

  testWidgets('failed grab offers an explicit retry; unsure state warns', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(1)])
      ..grabResult = const Result.err(AppError(ErrorCategory.serverError));
    await pumpEn(tester, api);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Download failed'), findsOneWidget);
    api.grabResult = const Result.err(AppError(ErrorCategory.timeout));
    await tester.tap(find.text('Download again'));
    await tester.pumpAndSettle();
    expect(
      find.text('May have been sent. Check the queue before trying again.'),
      findsOneWidget,
    );
    expect(api.count('grabRelease'), 2);
  });

  group('a maybe-sent release', () {
    ScriptedSonarrApi maybeSentApi() => ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(1)])
      ..grabResult = const Result.err(AppError(ErrorCategory.timeout));

    testWidgets('found in the queue is shown as grabbed, nothing is sent', (
      tester,
    ) async {
      final api = maybeSentApi();
      await pumpEn(tester, api);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(api.count('grabRelease'), 1);
      api.queueResult = Result.ok([
        ArrQueueItem(id: 5, title: fakeRelease(1).title),
      ]);
      await tester.tap(find.text('Download again'));
      await tester.pumpAndSettle();
      expect(api.count('queue'), 1);
      expect(api.count('grabRelease'), 1);
      expect(find.text('Sent to download client'), findsOneWidget);
      expect(find.text('Send again?'), findsNothing);
    });

    testWidgets('not in the queue asks first; cancel sends nothing', (
      tester,
    ) async {
      final api = maybeSentApi();
      await pumpEn(tester, api);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download again'));
      await tester.pumpAndSettle();
      expect(api.count('queue'), 1);
      expect(find.text('Send again?'), findsOneWidget);
      expect(
        find.text('This release may already have been sent. Send again?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.count('grabRelease'), 1);
    });

    testWidgets('confirming sends it once more', (tester) async {
      final api = maybeSentApi();
      await pumpEn(tester, api);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      api.grabResult = const Result.ok(null);
      await tester.tap(find.text('Download again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send again'));
      await tester.pumpAndSettle();
      expect(api.count('grabRelease'), 2);
      expect(find.text('Sent to download client'), findsOneWidget);
    });

    testWidgets('a failed queue check still asks before sending', (
      tester,
    ) async {
      final api = maybeSentApi();
      await pumpEn(tester, api);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      api.queueResult = const Result.err(
        AppError(ErrorCategory.networkUnreachable),
      );
      await tester.tap(find.text('Download again'));
      await tester.pumpAndSettle();
      expect(find.text('Send again?'), findsOneWidget);
      expect(api.count('grabRelease'), 1);
    });
  });

  testWidgets('rejected release needs a confirm that lists the reasons', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([
        fakeRelease(1, rejections: ['Not an upgrade']),
      ]);
    await pumpEn(tester, api);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Download a rejected release?'), findsOneWidget);
    expect(find.text('• Not an upgrade'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.count('grabRelease'), 0);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download anyway'));
    await tester.pumpAndSettle();
    expect(api.count('grabRelease'), 1);
    expect(find.text('Sent to download client'), findsOneWidget);
  });

  testWidgets('provider transition: a new server reloads, never old rows', (
    tester,
  ) async {
    final first = ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(1)]);
    final second = ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(2)]);
    final gate = Completer<void>();
    second.hook = (n) => n == 'releases' ? gate.future : Future.value();
    final active = NotifierProvider<_Holder, ScriptedSonarrApi>(
      () => _Holder(first),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sonarrSessionProvider.overrideWith(
            (ref) => SonarrSession(
              api: ref.watch(active),
              serverId: 'srv',
              cache: MemoryPayloadCache(),
              clock: DateTime.now,
            ),
          ),
        ],
        child: harnessApp(
          enVariant,
          const Scaffold(body: InteractiveSearchContent(target: episodeTarget)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('GRP1'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InteractiveSearchContent)),
    );
    container.read(active.notifier).set(second);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('GRP1'), findsNothing);
    expect(find.bySemanticsLabel('Searching for releases'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('GRP2'), findsOneWidget);
  });

  test('10,000 releases filter and sort within a time bound', () {
    final list = [
      for (var i = 0; i < 10000; i++)
        fakeRelease(i, size: i * 1000, ageMinutes: i % 500),
    ];
    final watch = Stopwatch()..start();
    final out = applyReleaseView(
      list,
      const ReleaseView(
        sort: ReleaseSort.size,
        decision: ReleaseDecision.accepted,
      ),
    );
    watch.stop();
    expect(out.length, 10000);
    expect(out.first.size, greaterThan(out.last.size));
    expect(watch.elapsedMilliseconds, lessThan(1500));
  });

  test('sort keys and reversal', () {
    final a = fakeRelease(1, size: 10, ageMinutes: 5, seeders: 1);
    final b = fakeRelease(2, size: 20, ageMinutes: 1, seeders: 9);
    List<int> ids(ReleaseView v) =>
        applyReleaseView([a, b], v).map((r) => r.releaseWeight).toList();
    expect(ids(const ReleaseView()), [1, 2]);
    expect(ids(const ReleaseView(sort: ReleaseSort.age)), [2, 1]);
    expect(ids(const ReleaseView(sort: ReleaseSort.size)), [2, 1]);
    expect(ids(const ReleaseView(sort: ReleaseSort.seeders)), [2, 1]);
    expect(ids(const ReleaseView(sort: ReleaseSort.size, reversed: true)), [
      1,
      2,
    ]);
    expect(ids(const ReleaseView(protocol: ArrProtocol.usenet)), isEmpty);
  });
}

class _Holder extends Notifier<ScriptedSonarrApi> {
  _Holder(this.initial);
  final ScriptedSonarrApi initial;
  @override
  ScriptedSonarrApi build() => initial;
  void set(ScriptedSonarrApi api) => state = api;
}
