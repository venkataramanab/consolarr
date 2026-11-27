// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/onboarding_screen.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  UiHarness h, {
  ValueChanged<ServiceKind>? onFinished,
  VoidCallback? onSkip,
  HarnessVariant variant = _v,
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(
    h.app(variant, OnboardingScreen(onFinished: onFinished, onSkip: onSkip)),
  );
  await tester.pumpAndSettle();
}

Future<void> _toDetails(WidgetTester tester) async {
  await _tap(tester, find.text('Get started'));
  await _tap(tester, find.text('Sonarr'));
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(_field('Display name'), 'Example Sonarr');
  await tester.enterText(_field('Address'), 'https://sonarr.example');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('welcome step explains the app and offers skip', (tester) async {
    var skipped = false;
    await _pump(tester, UiHarness(), onSkip: () => skipped = true);
    expect(find.text('Welcome to Consolarr'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    expect(skipped, isTrue);
  });

  testWidgets('choose step lists the supported services', (tester) async {
    await _pump(tester, UiHarness());
    await _tap(tester, find.text('Get started'));
    expect(find.text('Which service?'), findsOneWidget);
    expect(find.text('Sonarr'), findsOneWidget);
    expect(find.text('qBittorrent'), findsOneWidget);
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('details step has its own validation error state', (
    tester,
  ) async {
    await _pump(tester, UiHarness());
    await _toDetails(tester);
    expect(find.text('Server details'), findsOneWidget);
    await _tap(tester, find.text('Next'));
    expect(find.text('Server details'), findsOneWidget);
    expect(find.text('Enter a name for this server.'), findsOneWidget);
    expect(find.text('Enter the server address.'), findsOneWidget);
  });

  testWidgets('back goes to the previous step', (tester) async {
    await _pump(tester, UiHarness());
    await _toDetails(tester);
    await _tap(tester, find.text('Back'));
    expect(find.text('Which service?'), findsOneWidget);
  });

  testWidgets('finish is disabled until the test succeeded, then saves', (
    tester,
  ) async {
    ServiceKind? finished;
    final h = UiHarness();
    await _pump(tester, h, onFinished: (k) => finished = k);
    await _toDetails(tester);
    await _fill(tester);
    await _tap(tester, find.text('Next'));
    expect(find.text('Test and finish'), findsOneWidget);
    expect(find.text('Test the connection before finishing.'), findsOneWidget);
    final finish = find.widgetWithText(FilledButton, 'Finish');
    expect(tester.widget<FilledButton>(finish).onPressed, isNull);

    await _tap(tester, find.text('Test connection'));
    expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
    await _tap(tester, finish);
    expect(h.repo.saved.single.name, 'Example Sonarr');
    expect(finished, ServiceKind.sonarr);
  });

  testWidgets('a failed test keeps finish disabled and explains why', (
    tester,
  ) async {
    final h = UiHarness(
      tester: FakeTester([
        const ConnectionTestFailure(AppError(ErrorCategory.timeout)),
      ]),
    );
    await _pump(tester, h);
    await _toDetails(tester);
    await _fill(tester);
    await _tap(tester, find.text('Next'));
    await _tap(tester, find.text('Test connection'));
    expect(find.text('The server did not answer in time.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a save failure shows its own error on the last step', (
    tester,
  ) async {
    final h = UiHarness();
    h.repo.saveError = const AppError(
      ErrorCategory.parseError,
      debugDetail: 'invalid address',
    );
    await _pump(tester, h);
    await _toDetails(tester);
    await _fill(tester);
    await _tap(tester, find.text('Next'));
    await _tap(tester, find.text('Test connection'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Finish'));
    expect(find.text("Couldn't save the server"), findsOneWidget);
  });

  testWidgets('qBittorrent offers username and password, not an API key', (
    tester,
  ) async {
    await _pump(tester, UiHarness());
    await _tap(tester, find.text('Get started'));
    await _tap(tester, find.text('qBittorrent'));
    expect(_field('Username'), findsOneWidget);
  });

  testWidgets('the welcome step reports screen_viewed', (tester) async {
    final h = UiHarness();
    await _pump(tester, h);
    expect(h.analytics.events, contains('screen_viewed'));
  });

  group('matrix', () {
    testWidgets('welcome step: no overflow anywhere', (tester) async {
      await pumpMatrix(
        tester,
        (v) => UiHarness().app(v, const OnboardingScreen()),
      );
    });

    for (final locale in [const Locale('ar'), const Locale('en', 'XA')]) {
      testWidgets('every step is accessible at 2.0 in $locale', (tester) async {
        final v = HarnessVariant(
          size: const Size(320, 568),
          textScale: 2,
          locale: locale,
          brightness: Brightness.light,
        );
        final h = UiHarness();
        await _pump(tester, h, variant: v);
        await expectAccessible(tester);
        expectNoFrameworkExceptions(tester);
        await _tap(tester, find.byType(FilledButton).first);
        await expectAccessible(tester);
        await _tap(tester, find.byType(ListTile).first);
        // A scroll offset left over from the tap would clip the first fields.
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        expectNoFrameworkExceptions(tester);
        await expectAccessible(tester);
        await tester.enterText(_field(_label(tester, 0)), 'Example');
        await tester.pumpAndSettle();
        expectNoFrameworkExceptions(tester);
      });
    }
  });
}

String _label(WidgetTester tester, int index) {
  final fields = tester
      .widgetList<TextField>(find.byType(TextField))
      .map((f) => f.decoration?.labelText)
      .whereType<String>()
      .toList();
  return fields[index];
}
