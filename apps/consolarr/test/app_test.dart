// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('shows the localized placeholder home screen', (tester) async {
    final l10n = await _en();
    await tester.pumpWidget(const ProviderScope(child: ConsolarrApp()));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeTitle), findsOneWidget);
    expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
    expect(find.text(l10n.homeServerCount(0)), findsOneWidget);
  });

  testWidgets('navigates to About and back with the visible back button', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(const ProviderScope(child: ConsolarrApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.homeAboutTooltip));
    await tester.pumpAndSettle();
    expect(find.text(l10n.aboutIndependence), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
  });

  testWidgets('defaults to the dark theme', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ConsolarrApp()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('telemetry seams default to no-ops with consent off', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final consent = await container.read(consentStoreProvider).load();
    expect(consent.crashReports, isFalse);
    expect(consent.analytics, isFalse);
  });
}
