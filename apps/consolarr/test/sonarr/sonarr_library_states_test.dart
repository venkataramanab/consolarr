// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

const _en = Locale('en');

HarnessVariant _phone({
  double scale = 1,
  Locale locale = _en,
  Brightness brightness = Brightness.dark,
  Size size = const Size(360, 800),
}) => HarnessVariant(
  size: size,
  textScale: scale,
  locale: locale,
  brightness: brightness,
);

/// Every state the library can be in, by name.
Map<String, FakeLibraryNotifier Function()> _states() => {
  'loading': () => FakeLibraryNotifier(null),
  'data': () => FakeLibraryNotifier(dataState(fakeSeriesList(12))),
  'empty': () => FakeLibraryNotifier(dataState(const [])),
  'no server': () => FakeLibraryNotifier(const LibraryNoServer()),
  'offline with cache': () => FakeLibraryNotifier(
    dataState(
      fakeSeriesList(6),
      offlineError: const AppError(ErrorCategory.networkUnreachable),
      age: const Duration(hours: 3),
    ),
  ),
  'offline with empty cache': () => FakeLibraryNotifier(
    dataState(
      const [],
      offlineError: const AppError(ErrorCategory.timeout),
      age: const Duration(minutes: 5),
    ),
  ),
  'auth_failed': () => FakeLibraryNotifier(
    const LibraryFailure(AppError(ErrorCategory.authFailed)),
  ),
  'needs credentials': () => FakeLibraryNotifier(
    const LibraryFailure(
      AppError(ErrorCategory.authFailed, debugDetail: 'needs_credentials'),
    ),
  ),
  for (final c in ErrorCategory.values.where(
    (c) => c != ErrorCategory.authFailed,
  ))
    c.code: () => FakeLibraryNotifier(LibraryFailure(AppError(c))),
  'long titles': () => FakeLibraryNotifier(
    dataState([
      for (var i = 1; i <= 6; i++)
        fakeSeries(i, title: 'Example Show $i ${'Very Long Title ' * 12}'),
    ]),
  ),
};

void main() {
  group('every state: no overflow (sizes x scales x locales, dark)', () {
    for (final entry in _states().entries) {
      testWidgets(entry.key, (tester) async {
        for (final mode in LibraryViewMode.values) {
          await pumpMatrix(
            tester,
            (v) => libraryApp(v, notifier: entry.value(), mode: mode),
            variants: harnessMatrix(brightnesses: [Brightness.dark]),
          );
        }
      });
    }
  });

  group('main states: full matrix incl. light theme', () {
    for (final name in ['data', 'offline with cache', 'auth_failed']) {
      testWidgets(name, (tester) async {
        await pumpMatrix(
          tester,
          (v) => libraryApp(v, notifier: _states()[name]!()),
          variants: harnessMatrix(brightnesses: [Brightness.light]),
        );
      });
    }
  });

  group('accessibility guidelines', () {
    for (final entry in _states().entries) {
      testWidgets('${entry.key} at 1.0 (en) and 2.0 (ar, en_XA)', (
        tester,
      ) async {
        await pumpMatrix(
          tester,
          (v) => libraryApp(v, notifier: entry.value()),
          variants: [
            _phone(),
            _phone(scale: 2, locale: const Locale('ar')),
            _phone(scale: 2, locale: const Locale('en', 'XA')),
          ],
          verify: (v) => expectAccessible(tester),
        );
      });
    }

    testWidgets('list mode too', (tester) async {
      await pumpMatrix(
        tester,
        (v) => libraryApp(
          v,
          notifier: _states()['data']!(),
          mode: LibraryViewMode.list,
        ),
        variants: [
          _phone(),
          _phone(scale: 2, locale: const Locale('ar')),
        ],
        verify: (v) => expectAccessible(tester),
      );
    });
  });

  group('content', () {
    testWidgets('grid shows posters with status text and unmonitored badge', (
      tester,
    ) async {
      final v = _phone();
      applyVariantView(tester, v);
      await tester.pumpWidget(
        libraryApp(
          v,
          notifier: FakeLibraryNotifier(
            dataState([
              fakeSeries(1),
              fakeSeries(2, status: SeriesStatus.ended, monitored: false),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
      expect(find.text('Continuing'), findsOneWidget);
      expect(find.text('Ended'), findsOneWidget);
      expect(find.text('Unmonitored'), findsOneWidget);
      expect(find.textContaining('8/10'), findsWidgets);
    });

    testWidgets('list shows facts and a screen-reader label', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        libraryApp(
          v,
          mode: LibraryViewMode.list,
          notifier: FakeLibraryNotifier(
            dataState([
              fakeSeries(1, nextAiring: fixedNow.add(const Duration(days: 3))),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Airs in 3 days'), findsOneWidget);
      expect(find.textContaining('8/10 episodes'), findsWidgets);
      expect(find.textContaining('3.0 GB'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Example Show 1, Continuing, Monitored')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('offline banner states the cache age and keeps the list', (
      tester,
    ) async {
      final v = _phone();
      applyVariantView(tester, v);
      await tester.pumpWidget(
        libraryApp(v, notifier: _states()['offline with cache']!()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.textContaining('Updated 3 hours ago'), findsOneWidget);
      expect(find.text('Example Show 1'), findsOneWidget);
    });

    testWidgets('offline retry asks for a refresh', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      final notifier = _states()['offline with cache']!();
      await tester.pumpWidget(libraryApp(v, notifier: notifier));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(notifier.refreshCalls, 1);
    });

    testWidgets('unauthorized names the cause and offers the settings', (
      tester,
    ) async {
      final v = _phone();
      applyVariantView(tester, v);
      var opened = 0;
      await tester.pumpWidget(
        libraryApp(
          v,
          notifier: _states()['auth_failed']!(),
          onOpenServers: () => opened++,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sonarr rejected the sign-in'), findsOneWidget);
      expect(
        find.textContaining("A username and password don't work"),
        findsOneWidget,
      );
      await tester.tap(find.text('Check server settings'));
      expect(opened, 1);
    });

    testWidgets('unsupported version is its own state', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      await tester.pumpWidget(
        libraryApp(v, notifier: _states()['unsupported_version']!()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsupported Sonarr version'), findsOneWidget);
      expect(find.textContaining('version 3 or newer'), findsOneWidget);
    });

    testWidgets('no server offers to add one', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      var opened = 0;
      await tester.pumpWidget(
        libraryApp(
          v,
          notifier: _states()['no server']!(),
          onOpenServers: () => opened++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a server'));
      expect(opened, 1);
    });

    testWidgets('empty library offers to add a series', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      final notifier = _states()['empty']!();
      await tester.pumpWidget(libraryApp(v, notifier: notifier));
      await tester.pumpAndSettle();
      expect(find.text('No series yet'), findsOneWidget);
      expect(find.text('Add a series'), findsWidgets);
    });

    testWidgets('loading shows a layout-matching skeleton', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      await tester.pumpWidget(
        libraryApp(v, notifier: _states()['loading']!(), reduceMotion: false),
      );
      await tester.pump();
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(PosterCard), findsNothing);
    });

    testWidgets('skeleton is static under reduced motion', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      await tester.pumpWidget(libraryApp(v, notifier: _states()['loading']!()));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('toggle switches between grid and list and is labelled', (
      tester,
    ) async {
      final v = _phone();
      applyVariantView(tester, v);
      await tester.pumpWidget(libraryApp(v, notifier: _states()['data']!()));
      await tester.pumpAndSettle();
      expect(find.byType(PosterCard), findsWidgets);
      await tester.tap(find.byTooltip('Show as list'));
      await tester.pumpAndSettle();
      expect(find.byType(MediaListTile), findsWidgets);
      expect(find.byType(PosterCard), findsNothing);
      expect(find.byTooltip('Show as grid'), findsOneWidget);
    });

    testWidgets('pull to refresh keeps the content on screen', (tester) async {
      final v = _phone();
      applyVariantView(tester, v);
      final gate = Completer<void>();
      final notifier = FakeLibraryNotifier(
        dataState(fakeSeriesList(12)),
        onRefresh: () => gate.future,
      );
      await tester.pumpWidget(libraryApp(v, notifier: notifier));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(notifier.refreshCalls, 1);
      expect(find.text('Example Show 1'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Example Show 1'), findsOneWidget);
    });
  });
}
