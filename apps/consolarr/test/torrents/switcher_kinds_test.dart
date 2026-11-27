// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/application/servers_providers.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/server_switcher_sheet.dart';
import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:consolarr/features/torrents/data/torrents_prefs.dart';
import 'package:consolarr/features/torrents/torrents_routes.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:consolarr/src/database/app_database.dart';
import 'package:consolarr/src/navigation/destinations.dart';
import 'package:consolarr/src/providers.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import '../servers/ui/support.dart' as ui;
import 'support.dart';

ServerEntry _e(String id, String name, ServiceKind kind) => ServerEntry(
  profile: ui.profile(
    id,
    name: name,
    kind: kind,
    address: 'https://$id.example',
    authMode: AuthMode.basic,
  ),
  sortOrder: 0,
);

/// drift's stream cleanup leaves a zero-length timer after the widget tree is
/// gone; flush it so the test can end.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 5));
}

/// Calls [onSetActive] when `setActive` runs (before it changes anything).
class _RecordingRepo extends ui.FakeServerRepository {
  _RecordingRepo(List<ServerEntry> entries, this.onSetActive) : super(entries);

  final Future<void> Function() onSetActive;

  @override
  Future<void> setActive(ServiceKind kind, String id) async {
    await onSetActive();
    await super.setActive(kind, id);
  }
}

void main() {
  late ui.FakeServerRepository repo;
  late AppDatabase db;

  setUp(() {
    repo = ui.FakeServerRepository([
      _e('qb', 'Example qBittorrent', ServiceKind.qbittorrent),
      _e('tr', 'Example Transmission', ServiceKind.transmission),
      _e('dl', 'Example Deluge', ServiceKind.deluge),
      _e('so', 'Example Sonarr', ServiceKind.sonarr),
    ]);
    db = AppDatabase.memory();
    addTearDown(db.close);
  });

  Widget sheet(HarnessVariant v) => ProviderScope(
    retry: (_, _) => null,
    overrides: [
      serverRepositoryProvider.overrideWithValue(repo),
      databaseProvider.overrideWithValue(db),
      uiServersProvider.overrideWith((ref) => AsyncData(repo.entries)),
      serverHealthProvider.overrideWith((ref, id) => ServerHealth.healthy),
    ],
    child: harnessApp(
      v,
      Scaffold(
        body: ServerSwitcherSheet(
          kinds: torrentsDestination.effectiveSwitcherKinds,
          selectionKey: 'torrents.selected_kind',
        ),
      ),
    ),
  );

  testWidgets('lists every torrent server with its kind, never other kinds', (
    tester,
  ) async {
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(sheet(baseVariant));
    await tester.pumpAndSettle();
    expect(find.text('Example qBittorrent'), findsOneWidget);
    expect(find.text('Example Transmission'), findsOneWidget);
    expect(find.text('Example Deluge'), findsOneWidget);
    expect(find.text('Example Sonarr'), findsNothing);
    expect(find.textContaining('qBittorrent ·'), findsOneWidget);
    expect(find.textContaining('Transmission ·'), findsOneWidget);
    expect(find.textContaining('Deluge ·'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('picking Transmission activates it and remembers the kind', (
    tester,
  ) async {
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(sheet(baseVariant));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Transmission'));
    await tester.pumpAndSettle();
    expect(repo.active[ServiceKind.transmission], 'tr');
    final row = await tester.runAsync(
      () => (db.select(
        db.appStateRows,
      )..where((r) => r.key.equals('torrents.selected_kind'))).getSingle(),
    );
    expect(row!.value, 'transmission');
    await _dispose(tester);
  });

  testWidgets('picking a server activates it before the kind is stored', (
    tester,
  ) async {
    // The old order stored the kind first, so the list switched to the new
    // kind's previously active server for a moment (a flash) before the
    // chosen server became active.
    final seen = <String?>[];
    final recording = _RecordingRepo(repo.entries, () async {
      final row =
          await (db.select(db.appStateRows)
                ..where((r) => r.key.equals('torrents.selected_kind')))
              .getSingleOrNull();
      seen.add(row?.value);
    });
    repo = recording;
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(sheet(baseVariant));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Deluge'));
    await tester.pumpAndSettle();
    expect(seen, [null], reason: 'setActive ran before the kind was stored');
    final row = await tester.runAsync(
      () => (db.select(
        db.appStateRows,
      )..where((r) => r.key.equals('torrents.selected_kind'))).getSingle(),
    );
    expect(row!.value, 'deluge');
    await _dispose(tester);
  });

  testWidgets('the active server of the chosen kind is marked', (tester) async {
    repo.active[ServiceKind.qbittorrent] = 'qb';
    repo.active[ServiceKind.deluge] = 'dl';
    await db
        .into(db.appStateRows)
        .insertOnConflictUpdate(
          AppStateRowsCompanion.insert(
            key: 'torrents.selected_kind',
            value: 'deluge',
          ),
        );
    applyVariantView(tester, baseVariant);
    await tester.pumpWidget(sheet(baseVariant));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.textContaining('Deluge · Active'), findsOneWidget);
    expect(find.textContaining('qBittorrent · Active'), findsNothing);
    await _dispose(tester);
  });

  test('the destination follows the registry; one key for the selection', () {
    expect(
      torrentsDestination.effectiveSwitcherKinds,
      torrentClientFactories.keys.toSet(),
    );
    expect(torrentsDestination.kinds, torrentClientFactories.keys.toSet());
    expect(
      TorrentsPrefs.selectedKindKey,
      selectedKindKeyFor(torrentsDestination.id),
    );
  });

  test(
    'the Torrents destination uses switcherKinds and Sonarr is untouched',
    () {
      expect(torrentsDestination.switcherKinds, {
        ServiceKind.qbittorrent,
        ServiceKind.transmission,
        ServiceKind.deluge,
      });
      final sonarr = appDestinations.firstWhere((d) => d.id == 'sonarr');
      expect(sonarr.effectiveSwitcherKinds, {ServiceKind.sonarr});
    },
  );

  testWidgets('accessible in the stress matrix', (tester) async {
    await pumpMatrix(
      tester,
      sheet,
      variants: stressVariants,
      verify: (v) => expectAccessible(tester),
    );
    await _dispose(tester);
  });
}
