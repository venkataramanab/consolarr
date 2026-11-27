// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled, real fonts (Inter and Noto Sans Arabic, both SIL OFL;
/// plus Material icons when the Flutter SDK is available) so goldens render identically on every machine
/// instead of with the blocky `Ahem` test font.
///
/// Call once from `test/flutter_test_config.dart`:
///
/// ```dart
/// Future<void> testExecutable(FutureOr<void> Function() testMain) async {
///   await loadBundledFonts();
///   await testMain();
/// }
/// ```
Future<void> loadBundledFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const package = 'packages/design_system';
  final inter = FontLoader('$package/Inter')
    ..addFont(rootBundle.load('$package/assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('$package/assets/fonts/Inter-Bold.ttf'));
  await inter.load();

  const harness = 'packages/test_harness';
  // Registered under design_system's package prefix: theme text styles carry
  // `package: 'design_system'`, which Flutter also prepends to fallbacks.
  final arabic = FontLoader('$package/NotoSansArabic')
    ..addFont(
      rootBundle.load('$harness/assets/fonts/NotoSansArabic-Regular.ttf'),
    )
    ..addFont(rootBundle.load('$harness/assets/fonts/NotoSansArabic-Bold.ttf'));
  await arabic.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = flutterRoot == null
      ? null
      : File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
        );
  if (icons != null && icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

/// Font family fallbacks the harness theme uses so non-Latin text renders
/// with real glyphs in goldens.
const harnessFontFallback = ['NotoSansArabic'];
