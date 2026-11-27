// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

const _variant = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

void main() {
  testWidgets('10,000 series: only visible rows are built, and it scrolls', (
    tester,
  ) async {
    applyVariantView(tester, _variant);
    final big = fakeSeriesList(10000);
    for (final mode in LibraryViewMode.values) {
      // A fresh scope per mode (the saved view mode is read once per scope).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        libraryApp(
          _variant,
          notifier: FakeLibraryNotifier(dataState(big)),
          mode: mode,
        ),
      );
      await tester.pumpAndSettle();
      final built = mode == LibraryViewMode.grid
          ? find.byType(PosterCard).evaluate().length
          : find.byType(MediaListTile).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(60), reason: 'items must be built lazily');
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -3000),
        8000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsNothing);
      expectNoFrameworkExceptions(tester);
    }
  });

  testWidgets('0 series shows the empty state, not a blank list', (
    tester,
  ) async {
    applyVariantView(tester, _variant);
    await tester.pumpWidget(
      libraryApp(_variant, notifier: FakeLibraryNotifier(dataState(const []))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(PosterCard), findsNothing);
  });

  testWidgets('rebuild bound: scrolling builds each poster at most twice '
      '(once on entry, once for the first layout pass)', (tester) async {
    applyVariantView(tester, _variant);
    final source = CountingArtworkSource();
    await tester.pumpWidget(
      libraryApp(
        _variant,
        notifier: FakeLibraryNotifier(dataState(fakeSeriesList(300))),
        artwork: source,
      ),
    );
    await tester.pumpAndSettle();
    // Scroll down through ~12 screens in steps, one way.
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(source.requests, isNotEmpty);
    final worst = source.requests.values.reduce((a, b) => a > b ? a : b);
    expect(worst, lessThanOrEqualTo(2));
    // And we never touched far more items than the screens we scrolled.
    expect(source.requests.length, lessThan(300));
  });

  testWidgets('no network or database access when the screen is built', (
    tester,
  ) async {
    applyVariantView(tester, _variant);
    final recorder = AccessRecorder();
    await expectNoIoBeforeFirstFrame(
      tester,
      libraryApp(
        _variant,
        notifier: FakeLibraryNotifier(dataState(fakeSeriesList(5))),
      ),
      recorder: recorder,
    );
  });
}
