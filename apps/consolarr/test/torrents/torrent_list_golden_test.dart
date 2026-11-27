// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrents_providers.dart';
import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'support.dart';

void main() {
  testWidgets('golden: torrent list, data (en, dark, 360x800)', (tester) async {
    const variant = baseVariant;
    applyVariantView(tester, variant);
    await tester.pumpWidget(
      screenApp(
        variant,
        client: () async => FakeTorrentClient(torrents: allStates()),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/torrents_data_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: torrent list, offline (ar, light, 360x800)', (
    tester,
  ) async {
    const variant = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('ar'),
      brightness: Brightness.light,
    );
    applyVariantView(tester, variant);
    await tester.pumpWidget(
      screenApp(
        variant,
        client: () async =>
            FakeTorrentClient(torrents: allStates())..failFromCall = 2,
      ),
    );
    await tester.pumpAndSettle();
    await ProviderScope.containerOf(
      tester.element(find.byType(TorrentListScreen)),
    ).read(torrentListProvider.notifier).refresh();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/torrents_offline_ar_light_360x800.png'),
    );
  });
}
