// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:arr_api/arr_api.dart';
import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'library_harness.dart';
import 'support.dart';

void main() {
  testWidgets('golden: grid with data (en, dark, 360x800)', (tester) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
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
            fakeSeries(5),
            fakeSeries(6, status: SeriesStatus.ended),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_grid_en_dark_360x800.png'),
    );
  });

  testWidgets('golden: list, offline with cache (ar, light, 360x800)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('ar'),
      brightness: Brightness.light,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(
      libraryApp(
        v,
        mode: LibraryViewMode.list,
        notifier: FakeLibraryNotifier(
          dataState(
            [
              fakeSeries(1, nextAiring: fixedNow.add(const Duration(days: 2))),
              fakeSeries(2, status: SeriesStatus.ended, monitored: false),
              fakeSeries(3),
            ],
            offlineError: const AppError(ErrorCategory.networkUnreachable),
            age: const Duration(hours: 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sonarr_list_offline_ar_light_360x800.png'),
    );
  });
}
