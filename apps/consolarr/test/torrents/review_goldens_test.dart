// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/server_switcher_sheet.dart';
import 'package:consolarr/features/torrents/presentation/remove_dialog.dart';
import 'package:consolarr/features/torrents/torrents_routes.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../servers/ui/support.dart' as ui;
import 'support.dart';

const _enLight = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.light,
);

Future<void> _list(
  WidgetTester tester,
  HarnessVariant v,
  FakeTorrentClient client,
  String file,
) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(screenApp(v, client: () async => client));
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file.png'),
  );
}

void main() {
  testWidgets('golden: empty (en, light)', (tester) async {
    await _list(
      tester,
      _enLight,
      FakeTorrentClient(),
      'torrents_empty_en_light_360x800',
    );
  });

  testWidgets('golden: error (en, dark)', (tester) async {
    await _list(
      tester,
      baseVariant,
      FakeTorrentClient()..failTorrents(ErrorCategory.networkUnreachable),
      'torrents_error_en_dark_360x800',
    );
  });

  testWidgets('golden: data at text scale 2.0 (en, light)', (tester) async {
    await _list(
      tester,
      const HarnessVariant(
        size: Size(360, 800),
        textScale: 2,
        locale: Locale('en'),
        brightness: Brightness.light,
      ),
      FakeTorrentClient(torrents: allStates().take(4).toList()),
      'torrents_data_en_light_360x800_scale2',
    );
  });

  testWidgets('golden: data in the en_XA pseudo-locale (dark)', (tester) async {
    await _list(
      tester,
      const HarnessVariant(
        size: Size(360, 800),
        textScale: 1,
        locale: Locale('en', 'XA'),
        brightness: Brightness.dark,
      ),
      FakeTorrentClient(torrents: allStates().take(4).toList()),
      'torrents_data_en_xa_dark_360x800',
    );
  });

  testWidgets('golden: remove dialog (en, dark)', (tester) async {
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(
      harnessApp(
        baseVariant,
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showRemoveDialog(context, 'Example Torrent'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/torrent_remove_dialog_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: server switcher with all torrent kinds (en, light)', (
    tester,
  ) async {
    ServerEntry entry(String id, String name, ServiceKind kind) => ServerEntry(
      profile: ui.profile(
        id,
        name: name,
        kind: kind,
        address: 'https://$id.example',
        authMode: AuthMode.basic,
      ),
      sortOrder: 0,
    );
    final repo = ui.FakeServerRepository([
      entry('qb', 'Example qBittorrent', ServiceKind.qbittorrent),
      entry('tr', 'Example Transmission', ServiceKind.transmission),
      entry('dl', 'Example Deluge', ServiceKind.deluge),
    ])..active[ServiceKind.transmission] = 'tr';
    final db = AppDatabase.memory();
    addTearDown(db.close);
    applyVariantView(tester, _enLight);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          serverRepositoryProvider.overrideWithValue(repo),
          databaseProvider.overrideWithValue(db),
          uiServersProvider.overrideWith((ref) => AsyncData(repo.entries)),
          serverHealthProvider.overrideWith((ref, id) => ServerHealth.healthy),
        ],
        child: harnessApp(
          _enLight,
          Scaffold(
            body: ServerSwitcherSheet(
              kinds: torrentsDestination.effectiveSwitcherKinds,
              selectionKey: 'torrents.selected_kind',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/torrent_switcher_en_light_360x800.png'),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 5));
  });
}
