// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/arr_common/presentation/removal_dialog.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_body.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'detail_harness.dart';
import 'fakes.dart';
import 'library_harness.dart';
import 'support.dart';
import 'tab_harness.dart';

const _enDark = HarnessVariant(
  size: Size(360, 800),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

void main() {
  testWidgets('golden: edit series sheet (en, dark, 360x800)', (tester) async {
    applyVariantView(tester, _enDark);
    await tester.pumpWidget(detailApp(_enDark, api: detailApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/edit_series_sheet_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: queue removal dialog (en, dark, 360x800)', (
    tester,
  ) async {
    applyVariantView(tester, _enDark);
    await tester.pumpWidget(
      harnessApp(
        _enDark,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showArrQueueRemovalDialog(
                context: context,
                itemLabel: 'Example Show 1',
                serviceName: 'Sonarr',
                kind: ServiceKind.sonarr,
                onConfirm: (_) async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/queue_removal_dialog_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: Sonarr home, library tab (en_XA, dark, 320x568)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(320, 568),
      textScale: 1,
      locale: Locale('en', 'XA'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(
      libraryApp(
        v,
        notifier: FakeLibraryNotifier(
          dataState([
            fakeSeries(1),
            fakeSeries(2, status: SeriesStatus.ended, monitored: false),
            fakeSeries(3, title: 'Example Show With A Much Longer Title'),
            fakeSeries(4, status: SeriesStatus.upcoming, files: 0),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_home_xa_dark_320x568.png'),
    );
  });

  testWidgets('golden: wanted (ar, dark, 320x568, text scale 2.0)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(320, 568),
      textScale: 2,
      locale: Locale('ar'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    final api = ScriptedSonarrApi()
      ..wantedResult = Result.ok(
        ArrPage(
          records: [
            for (var i = 1; i <= 3; i++)
              SonarrEpisode(
                id: i,
                seriesId: i,
                seasonNumber: 1,
                episodeNumber: i,
                title: 'Example Episode $i',
                airDateUtc: DateTime.utc(2026, 4, 20, 12),
                monitored: true,
                series: fakeSeries(i),
              ),
          ],
          pageSize: 50,
          totalRecords: 3,
        ),
      );
    await tester.pumpWidget(
      tabApp(
        v,
        api: api,
        body: (context, padding) => WantedBody(
          padding: padding,
          onManualSearch: (context, episode, title) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_wanted_ar_dark_320x568_x2.png'),
    );
  });
}
