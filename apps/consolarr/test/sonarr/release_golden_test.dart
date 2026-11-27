// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'add_harness.dart';
import 'fakes.dart';
import 'release_harness.dart';

void main() {
  testWidgets('golden: release sheet with rejected row (en, dark)', (
    tester,
  ) async {
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([
        fakeRelease(1),
        fakeRelease(2, rejections: ['Not an upgrade', 'Size too big']),
        fakeRelease(3, seeders: 2, ageMinutes: 60 * 50),
      ]);
    await pumpEn(tester, api);
    await tester.tap(find.byTooltip('Show details').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/release_sheet_en_dark_412x915.png'),
    );
  });

  testWidgets('golden: release sheet (ar, light, 320x568)', (tester) async {
    const v = HarnessVariant(
      size: Size(320, 568),
      textScale: 1,
      locale: Locale('ar'),
      brightness: Brightness.light,
    );
    applyVariantView(tester, v);
    final api = ScriptedSonarrApi()
      ..releasesResult = Result.ok([fakeRelease(1), fakeRelease(2)]);
    await tester.pumpWidget(releaseApp(v, api));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/release_sheet_ar_light_320x568.png'),
    );
  });

  testWidgets('golden: add results with library marker (en_XA, dark)', (
    tester,
  ) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en', 'XA'),
      brightness: Brightness.dark,
    );
    applyVariantView(tester, v);
    final api = addApi(
      results: [fakeLookup(1), fakeLookup(2, inLibrary: true), fakeLookup(3)],
    );
    await tester.pumpWidget(addApp(v, api, initialTerm: 'example'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/add_results_xa_dark_360x800.png'),
    );
  });

  testWidgets('golden: add options sheet (en, light)', (tester) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.light,
    );
    applyVariantView(tester, v);
    final api = addApi(results: [fakeLookup(1)]);
    await tester.pumpWidget(addApp(v, api, initialTerm: 'example'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Show 1'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/add_options_en_light_360x800.png'),
    );
  });
}
