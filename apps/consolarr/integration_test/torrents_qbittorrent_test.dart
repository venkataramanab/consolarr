// SPDX-License-Identifier: GPL-3.0-or-later

// Nightly emulator test against the seeded qBittorrent container (see
// tools/integration): opens the torrent list and the detail sheet, pauses and
// resumes the seeded torrent and adds a magnet link. Fake data only.

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
const _qbitPort = String.fromEnvironment('IT_QBIT_PORT');
const _qbitUser = String.fromEnvironment('IT_QBIT_USERNAME');
const _qbitPassword = String.fromEnvironment('IT_QBIT_PASSWORD');

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

  testWidgets('torrent list, detail, limits, pause/resume and add', (
    tester,
  ) async {
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
            name: 'Example qBittorrent',
            kind: ServiceKind.qbittorrent,
            address: 'http://$_host:$_qbitPort',
            authMode: AuthMode.basic,
            allowCleartext: true,
            credentials: ServerCredentials(
              username: _qbitUser,
              password: _qbitPassword,
            ),
          ),
        );
    expect(saved.isOk, isTrue);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.navTorrents));
    await _pumpUntil(tester, find.byType(ProgressFillRow));

    // Detail sheet of the first torrent.
    await tester.tap(find.byType(ProgressFillRow).first);
    await _pumpUntil(tester, find.text(l10n.torDetailRatioLabel));
    await tester.tap(find.byTooltip(l10n.torDetailClose));
    await tester.pumpAndSettle();

    // Pause, then resume, through the row menu.
    await tester.longPress(find.byType(ProgressFillRow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.torActionPause));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(ProgressFillRow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.torActionResume));
    await tester.pumpAndSettle();

    // Add a magnet link.
    await tester.tap(find.byTooltip(l10n.torAddAction));
    await _pumpUntil(tester, find.text(l10n.torAddSourceLabel));
    await tester.enterText(
      find.byType(TextField).first,
      'magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      '&dn=Example+Linux+ISO',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.torAddButton));
    await _pumpUntil(tester, find.text(l10n.torAddAdded));
  });
}
