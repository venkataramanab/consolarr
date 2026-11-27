// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

/// The capabilities each client reports (the matrix of the brief).
const _matrix = <String, (ServiceKind, TorrentCapabilities)>{
  'qBittorrent': (
    ServiceKind.qbittorrent,
    TorrentCapabilities(
      alternativeSpeed: true,
      labelModel: LabelModel.category,
      tags: true,
    ),
  ),
  'Transmission (RPC 16+)': (
    ServiceKind.transmission,
    TorrentCapabilities(
      alternativeSpeed: true,
      tags: true,
      availability: false,
    ),
  ),
  'Transmission (older RPC)': (
    ServiceKind.transmission,
    TorrentCapabilities(alternativeSpeed: true, availability: false),
  ),
  'Deluge (label plugin)': (
    ServiceKind.deluge,
    TorrentCapabilities(labelModel: LabelModel.label),
  ),
  'Deluge (no label plugin)': (ServiceKind.deluge, TorrentCapabilities()),
};

Future<void> _show(
  WidgetTester tester,
  Widget child,
  FakeTorrentClient c,
) async {
  applyVariantView(tester, baseVariant);
  await tester.pumpWidget(sheetApp(baseVariant, child, client: c));
  await tester.pumpAndSettle();
}

void main() {
  _matrix.forEach((name, entry) {
    final (kind, caps) = entry;
    group('controls for $name', () {
      FakeTorrentClient make() =>
          FakeTorrentClient(kind: kind)..capabilities = caps;

      testWidgets('add sheet shows exactly the supported fields', (
        tester,
      ) async {
        await _show(tester, const AddTorrentSheet(), make());
        // The detected capabilities arrive with the first list.
        await tester.tap(find.text('Options'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Save path'), findsOneWidget);
        expect(find.text('Start paused'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'Category'),
          caps.labelModel == LabelModel.category
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.widgetWithText(TextField, 'Label'),
          caps.labelModel == LabelModel.label ? findsOneWidget : findsNothing,
        );
        expect(
          find.widgetWithText(TextField, 'Tags'),
          caps.tags ? findsOneWidget : findsNothing,
        );
        // Deluge without the plugin explains why there is no label field.
        expect(
          find.text('Labels need the Label plugin on your Deluge server.'),
          kind == ServiceKind.deluge && !caps.hasLabel
              ? findsOneWidget
              : findsNothing,
        );
      });

      testWidgets(
        'limits sheet shows the alternative switch only where it exists',
        (tester) async {
          final c = make()
            ..limits = SpeedLimitsState(
              download: 0,
              upload: 0,
              alternativeActive: caps.alternativeSpeed ? false : null,
            );
          await _show(tester, const SpeedLimitsSheet(), c);
          expect(
            find.byType(Switch),
            caps.alternativeSpeed ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('This client has no alternative speed limits.'),
            caps.alternativeSpeed ? findsNothing : findsOneWidget,
          );
          // Nothing is "Later": no force start / recheck / per-torrent limits UI.
          expect(find.textContaining('Force'), findsNothing);
          expect(find.textContaining('Recheck'), findsNothing);
        },
      );
    });
  });

  test('every client kind has a capability set in the matrix', () {
    expect(
      {for (final e in _matrix.values) e.$1},
      {ServiceKind.qbittorrent, ServiceKind.transmission, ServiceKind.deluge},
    );
  });
}
