// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'detail_harness.dart';
import 'fakes.dart';

Future<void> _golden(
  WidgetTester tester,
  HarnessVariant v,
  ScriptedSonarrApi api,
  String file, {
  MemoryPayloadCache? cache,
}) async {
  applyVariantView(tester, v);
  await tester.pumpWidget(detailApp(v, api: api, cache: cache));
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$file'),
  );
}

void main() {
  testWidgets('golden: detail with data (en, dark, 360x800)', (tester) async {
    await _golden(
      tester,
      const HarnessVariant(
        size: Size(360, 800),
        textScale: 1,
        locale: Locale('en'),
        brightness: Brightness.dark,
      ),
      detailApi(),
      'detail_data_en_dark_360x800.png',
    );
  });

  testWidgets('golden: detail not found (en_XA, dark, 320x568)', (
    tester,
  ) async {
    await _golden(
      tester,
      const HarnessVariant(
        size: Size(320, 568),
        textScale: 1,
        locale: Locale('en', 'XA'),
        brightness: Brightness.dark,
      ),
      ScriptedSonarrApi()
        ..detailResult = const Result.err(AppError(ErrorCategory.notFound)),
      'detail_gone_xa_dark_320x568.png',
    );
  });

  testWidgets('golden: detail offline (ar, light, 360x800)', (tester) async {
    final cache = MemoryPayloadCache();
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('ar'),
      brightness: Brightness.light,
    );
    applyVariantView(tester, v);
    await tester.pumpWidget(detailApp(v, api: detailApi(), cache: cache));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _golden(
      tester,
      v,
      ScriptedSonarrApi()
        ..detailResult = const Result.err(AppError(ErrorCategory.timeout)),
      'detail_offline_ar_light_360x800.png',
      cache: cache,
    );
  });
}
