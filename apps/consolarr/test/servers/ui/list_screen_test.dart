// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/servers/presentation/servers_list_screen.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

const _v = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

List<ServerEntry> _three() => [
  entry('a', name: 'Example Sonarr', isStartup: true),
  entry(
    'b',
    name: 'Example qBittorrent',
    kind: ServiceKind.qbittorrent,
    address: 'http://192.0.2.10:8080',
    allowCleartext: true,
    sortOrder: 1,
  ),
  entry('c', name: 'Broken', needsCredentials: true, sortOrder: 2),
];

const _health = {
  'a': ServerHealth.healthy,
  'b': ServerHealth.unreachable,
  'c': ServerHealth.unauthorized,
};

Future<void> _pump(
  WidgetTester tester,
  UiHarness h, {
  HarnessVariant variant = _v,
}) async {
  applyVariantView(tester, variant);
  await tester.pumpWidget(h.app(variant, const ServersListScreen()));
  await tester.pump();
  await tester.pump();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServersListScreen)));

void main() {
  testWidgets('loading shows skeletons', (tester) async {
    await _pump(tester, UiHarness(neverLoads: true));
    expect(find.text('Servers'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectNoFrameworkExceptions(tester);
  });

  testWidgets('empty state offers the first-run action', (tester) async {
    await _pump(tester, UiHarness());
    expect(find.text('No servers yet'), findsOneWidget);
    expect(find.text('Add your first server'), findsOneWidget);
  });

  testWidgets('load error offers retry', (tester) async {
    await _pump(tester, UiHarness(listError: true));
    expect(find.text("Couldn't load your servers"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('rows show health as icon + text, badges and kind', (
    tester,
  ) async {
    await _pump(tester, UiHarness(servers: _three(), health: _health));
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Unreachable'), findsOneWidget);
    expect(find.text('Sign-in failed'), findsOneWidget);
    expect(find.text('Plain http'), findsOneWidget);
    expect(find.text('Needs credentials'), findsOneWidget);
    expect(find.text('Opens at launch'), findsOneWidget);
    expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
  });

  testWidgets('health that is still being checked says so', (tester) async {
    await _pump(tester, UiHarness(servers: _three()));
    expect(find.text('Checking…'), findsNWidgets(3));
  });

  testWidgets('menu offers non-drag reorder, active, startup and delete', (
    tester,
  ) async {
    final h = UiHarness(servers: _three(), health: _health);
    await _pump(tester, h);
    await tester.tap(find.byTooltip('More actions for Example qBittorrent'));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(h.repo.lastOrder, ['b', 'a', 'c']);

    await tester.tap(find.byTooltip('More actions for Example Sonarr'));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    await tester.tap(find.text('Make active'));
    await tester.pumpAndSettle();
    expect(h.repo.active[ServiceKind.sonarr], 'a');

    await tester.tap(find.byTooltip('More actions for Broken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open at launch'));
    await tester.pumpAndSettle();
    expect(h.repo.startup, 'c');
  });

  testWidgets('delete spells out the consequences; cancel keeps the server', (
    tester,
  ) async {
    final h = UiHarness(servers: _three(), health: _health);
    await _pump(tester, h);
    await tester.tap(find.byTooltip('More actions for Broken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Broken?'), findsOneWidget);
    expect(find.textContaining('trusted certificate'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.repo.deleted, isEmpty);
  });

  testWidgets('confirming the delete dialog deletes', (tester) async {
    final h = UiHarness(servers: _three(), health: _health);
    await _pump(tester, h);
    await tester.tap(find.byTooltip('More actions for Broken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.repo.deleted, ['c']);
  });

  testWidgets('pull to refresh rechecks health', (tester) async {
    final h = UiHarness(servers: _three(), health: _health);
    await _pump(tester, h);
    await tester.fling(find.text('Example Sonarr'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
    expect(_l10n(tester).serversTitle, 'Servers');
  });

  testWidgets('100 servers, very long names and addresses do not overflow', (
    tester,
  ) async {
    final many = [
      for (var i = 0; i < 100; i++)
        entry(
          's$i',
          name: 'Example server number $i ${'very long name ' * 8}',
          address: 'https://${'a' * 50}.example',
          sortOrder: i,
        ),
    ];
    await _pump(tester, UiHarness(servers: many));
    expectNoFrameworkExceptions(tester);
    expect(find.byType(Scrollable), findsWidgets);
  });

  group('matrix', () {
    testWidgets('no overflow in every state, size, scale, locale and theme', (
      tester,
    ) async {
      final states = <UiHarness Function()>[
        () => UiHarness(neverLoads: true),
        UiHarness.new,
        () => UiHarness(listError: true),
        () => UiHarness(servers: _three(), health: _health),
      ];
      for (final make in states) {
        await pumpMatrix(
          tester,
          (v) => make().app(v, const ServersListScreen()),
        );
      }
    });

    testWidgets('accessibility at 2.0 in ar and en_XA, and 1.0 in en', (
      tester,
    ) async {
      for (final locales in [
        [const Locale('ar'), const Locale('en', 'XA')],
        [const Locale('en')],
      ]) {
        await pumpMatrix(
          tester,
          (v) => UiHarness(
            servers: _three(),
            health: _health,
          ).app(v, const ServersListScreen()),
          variants: harnessMatrix(
            textScales: [locales.length == 2 ? 2 : 1],
            locales: locales,
          ),
          verify: (_) => expectAccessible(tester),
        );
      }
    });
  });
}
