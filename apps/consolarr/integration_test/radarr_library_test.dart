// SPDX-License-Identifier: GPL-3.0-or-later

// Nightly emulator test against a real Radarr container. It only runs when
// `IT_RADARR_PORT` (and the other defines below) are given; the nightly stack
// does not seed Radarr yet (see the PR for the requested container and runner
// line), so without them the test is skipped.

import 'package:consolarr/consolarr.dart';
import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

const _host = String.fromEnvironment('IT_HOST');
const _radarrPort = String.fromEnvironment('IT_RADARR_PORT');
const _radarrKey = String.fromEnvironment('IT_RADARR_API_KEY');

Future<void> _pumpUntil(
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'adds a Radarr server, opens the library, the calendar and the queue',
    skip: _radarrPort.isEmpty,
    (tester) async {
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
              name: 'Example Radarr',
              kind: ServiceKind.radarr,
              address: 'http://$_host:$_radarrPort',
              allowCleartext: true,
              credentials: ServerCredentials(apiKey: _radarrKey),
            ),
          );
      expect(saved.isOk, isTrue);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.navRadarr));
      await _pumpUntil(tester, find.byType(PosterCard));
      expect(find.byType(PosterCard), findsWidgets);

      await tester.tap(find.text(l10n.radarrTabCalendar));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.radarrTabQueue));
      await tester.pumpAndSettle();
      expect(find.text(l10n.radarrQueueEmptyHeadline), findsOneWidget);
    },
  );
}
