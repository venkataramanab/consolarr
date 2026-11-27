// SPDX-License-Identifier: GPL-3.0-or-later

// Shared setup of the Sonarr emulator tests (see tools/integration): starts the
// app, adds the seeded Sonarr server and opens the Sonarr tab.

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

const _host = String.fromEnvironment('IT_HOST');
const _sonarrPort = String.fromEnvironment('IT_SONARR_PORT');
const _sonarrKey = String.fromEnvironment('IT_SONARR_API_KEY');

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Starts the app with the seeded Sonarr server active and opens its tab.
Future<AppLocalizations> openSonarr(WidgetTester tester) async {
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ConsolarrApp(),
    ),
  );
  await tester.pumpAndSettle();
  final saved = await container
      .read(serverRepositoryProvider)
      .save(
        const ServerDraft(
          name: 'Example Sonarr',
          kind: ServiceKind.sonarr,
          address: 'http://$_host:$_sonarrPort',
          allowCleartext: true,
          credentials: ServerCredentials(apiKey: _sonarrKey),
        ),
      );
  expect(saved.isOk, isTrue);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.navSonarr));
  await tester.pump(const Duration(milliseconds: 500));
  return l10n;
}
