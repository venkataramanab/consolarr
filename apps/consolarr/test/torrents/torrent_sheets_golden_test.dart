// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/add_torrent_sheet.dart';
import 'package:consolarr/features/torrents/presentation/speed_limits_sheet.dart';
import 'package:consolarr/features/torrents/presentation/torrent_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';
import 'package:torrent_clients/torrent_clients.dart';

import 'support.dart';

const _ar = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('ar'),
  brightness: Brightness.light,
);

Future<void> _golden(
  WidgetTester tester,
  HarnessVariant v,
  Widget sheet,
  String file, {
  FakeTorrentClient? client,
  Future<void> Function()? before,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(
    sheetApp(v, sheet, client: client ?? FakeTorrentClient()),
  );
  await tester.pumpAndSettle();
  await before?.call();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file.png'),
  );
}

void main() {
  testWidgets('golden: add sheet with a parsed link (en, dark)', (
    tester,
  ) async {
    await _golden(
      tester,
      baseVariant,
      const AddTorrentSheet(),
      'torrent_add_en_dark_360x800',
      before: () async {
        await tester.enterText(
          find.byType(TextField).first,
          'magnet:?xt=urn:btih:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&dn=Example+Linux+ISO',
        );
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('golden: add sheet, invalid link (ar, light)', (tester) async {
    await _golden(
      tester,
      _ar,
      const AddTorrentSheet(),
      'torrent_add_invalid_ar_light_360x800',
      before: () async {
        await tester.enterText(
          find.byType(TextField).first,
          'ftp://files.example/a',
        );
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('golden: detail sheet (en, dark)', (tester) async {
    await _golden(
      tester,
      baseVariant,
      const TorrentDetailSheet(hash: 'hash1'),
      'torrent_detail_en_dark_360x800',
    );
  });

  testWidgets('golden: detail sheet (ar, light)', (tester) async {
    await _golden(
      tester,
      _ar,
      const TorrentDetailSheet(hash: 'hash1'),
      'torrent_detail_ar_light_360x800',
    );
  });

  testWidgets('golden: speed limits sheet (en, dark)', (tester) async {
    await _golden(
      tester,
      baseVariant,
      const SpeedLimitsSheet(),
      'torrent_limits_en_dark_360x800',
      client: FakeTorrentClient()
        ..limits = const SpeedLimitsState(
          download: 2 * 1024 * 1024,
          upload: 512 * 1024,
          alternativeActive: false,
        ),
    );
  });

  testWidgets('golden: speed limits sheet (ar, light)', (tester) async {
    await _golden(
      tester,
      _ar,
      const SpeedLimitsSheet(),
      'torrent_limits_ar_light_360x800',
    );
  });
}
