// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/data/settings_store.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:security/security.dart';
import 'package:material_ui/material_ui.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Widget _scope() => ProviderScope(
  overrides: [
    databaseProvider.overrideWith((ref) {
      final db = AppDatabase.memory();
      ref.onDispose(db.close);
      return db;
    }),
    secretStoreProvider.overrideWithValue(InMemorySecretStore()),
  ],
  child: const ConsolarrApp(),
);

/// Unmounts the app so drift's stream-cleanup timers fire before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('shows the first-run home screen with a setup prompt', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeTitle), findsWidgets);
    expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
    expect(find.text(l10n.homeSetupCta), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('navigates to About and back with the visible back button', (
    tester,
  ) async {
    final l10n = await _en();
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.homeAboutTooltip));
    await tester.pumpAndSettle();
    expect(find.text(l10n.aboutIndependence), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.homeEmptyHeading), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('defaults to the dark theme', (tester) async {
    await tester.pumpWidget(_scope());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    await _unmount(tester);
  });

  testWidgets('telemetry seams default to no-ops with consent off', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);
    final consent = await container.read(consentStoreProvider).load();
    expect(consent.crashReports, isFalse);
    expect(consent.analytics, isFalse);
  });
}
