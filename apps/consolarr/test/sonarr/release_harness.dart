// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/search/interactive_search_sheet.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'fakes.dart';

/// 320x568 and a large phone, every locale and both text scales, dark only.
final releaseVariants = harnessMatrix(
  sizes: const [Size(320, 568), Size(412, 915)],
  brightnesses: const [Brightness.dark],
);

const episodeTarget = InteractiveSearchTarget.episode(7);

/// The release sheet content inside the harness app.
Widget releaseApp(
  HarnessVariant variant,
  ScriptedSonarrApi api, {
  InteractiveSearchTarget target = episodeTarget,
  List<Override> extra = const [],
}) => ProviderScope(
  overrides: [...sonarrTestOverrides(api), ...extra],
  child: harnessApp(
    variant,
    ConsolarrEffectsScope(
      reduceMotion: true,
      child: Scaffold(body: InteractiveSearchContent(target: target)),
    ),
  ),
);

/// English at 412x915, scale 1.0, for text assertions.
const enVariant = HarnessVariant(
  size: Size(412, 915),
  textScale: 1,
  locale: Locale('en'),
  brightness: Brightness.dark,
);

/// Pumps the sheet once in [enVariant] and settles.
Future<void> pumpEn(WidgetTester tester, ScriptedSonarrApi api) async {
  applyVariantView(tester, enVariant);
  await tester.pumpWidget(releaseApp(enVariant, api));
  await tester.pumpAndSettle();
}
