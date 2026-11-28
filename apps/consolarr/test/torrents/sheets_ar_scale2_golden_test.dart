// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:consolarr/features/torrents/presentation/remove_dialog.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

/// The hardest corner: smallest phone, right-to-left, largest text.
const _arX2 = HarnessVariant(
  size: Size(320, 568),
  textScale: 2,
  locale: Locale('ar'),
  brightness: Brightness.light,
);

Future<void> _golden(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) show,
  String file, {
  FakeTorrentClient? client,
}) async {
  applyVariantView(tester, _arX2);
  await tester.pumpWidget(
    sheetApp(
      _arX2,
      Center(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => show(context),
            child: const Text('open'),
          ),
        ),
      ),
      client: client ?? FakeTorrentClient(),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file.png'),
  );
}

void main() {
  testWidgets('golden: add sheet (ar, light, 320 wide, scale 2)', (
    tester,
  ) async {
    await _golden(
      tester,
      showAddTorrentSheet,
      'torrent_add_ar_light_320x568_x2',
    );
  });

  testWidgets('golden: detail sheet (ar, light, 320 wide, scale 2)', (
    tester,
  ) async {
    await _golden(
      tester,
      (c) => showTorrentDetailSheet(c, 'hash1'),
      'torrent_detail_ar_light_320x568_x2',
    );
  });

  testWidgets('golden: speed limits sheet (ar, light, 320 wide, scale 2)', (
    tester,
  ) async {
    await _golden(
      tester,
      showSpeedLimitsSheet,
      'torrent_limits_ar_light_320x568_x2',
      client: FakeTorrentClient()
        ..limits = const SpeedLimitsState(
          download: 2 * 1024 * 1024,
          upload: 512 * 1024,
          alternativeActive: false,
        ),
    );
  });

  testWidgets('golden: remove dialog (ar, light, 320 wide, scale 2)', (
    tester,
  ) async {
    await _golden(
      tester,
      (c) => showRemoveDialog(c, 'Example Torrent'),
      'torrent_remove_dialog_ar_light_320x568_x2',
    );
  });
}
