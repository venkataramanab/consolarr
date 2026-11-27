// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:test_harness/src/fonts.dart';

/// Phone sizes (logical pixels) every screen must survive.
const harnessSizes = [Size(320, 568), Size(360, 800), Size(412, 915)];

/// System text scales every screen must survive.
const harnessTextScales = [1.0, 2.0];

/// Locales: English, the generated pseudo-locale and a real RTL language.
const harnessLocales = [Locale('en'), Locale('en', 'XA'), Locale('ar')];

/// Themes.
const harnessBrightnesses = [Brightness.dark, Brightness.light];

/// One combination of size, text scale, locale and theme.
class HarnessVariant {
  const HarnessVariant({
    required this.size,
    required this.textScale,
    required this.locale,
    required this.brightness,
  });

  final Size size;
  final double textScale;
  final Locale locale;
  final Brightness brightness;

  bool get isRtl => locale.languageCode == 'ar';

  String get label =>
      '${size.width.toInt()}x${size.height.toInt()} '
      'textScale=$textScale locale=$locale ${brightness.name}';

  @override
  String toString() => label;
}

/// The full cross product (3 sizes x 2 scales x 3 locales x 2 themes).
List<HarnessVariant> harnessMatrix({
  List<Size> sizes = harnessSizes,
  List<double> textScales = harnessTextScales,
  List<Locale> locales = harnessLocales,
  List<Brightness> brightnesses = harnessBrightnesses,
}) => [
  for (final size in sizes)
    for (final scale in textScales)
      for (final locale in locales)
        for (final brightness in brightnesses)
          HarnessVariant(
            size: size,
            textScale: scale,
            locale: locale,
            brightness: brightness,
          ),
];

ThemeData _withFallback(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamilyFallback: harnessFontFallback),
  appBarTheme: theme.appBarTheme.copyWith(
    titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
      fontFamilyFallback: harnessFontFallback,
    ),
  ),
);

/// A [MaterialApp] configured for [variant] (theme, locale, text scale,
/// localizations) around [home].
Widget harnessApp(HarnessVariant variant, Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _withFallback(ConsolarrTheme.light()),
    darkTheme: _withFallback(ConsolarrTheme.dark()),
    themeMode: variant.brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    locale: variant.locale,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(variant.textScale)),
      child: child!,
    ),
    home: home,
  );
}

/// Sizes the test surface to [variant] (device pixel ratio 1.0).
void applyVariantView(WidgetTester tester, HarnessVariant variant) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = variant.size;
  addTearDown(tester.view.reset);
}

/// Drains every pending framework exception and fails if any occurred.
///
/// `RenderFlex` overflows are reported by the framework as exceptions; they
/// are called out explicitly in the failure message.
void expectNoFrameworkExceptions(WidgetTester tester, {String? context}) {
  final problems = <String>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    final text = exception.toString();
    final overflow = text.contains('overflowed');
    problems.add(
      '${overflow ? 'RenderFlex overflow' : 'Exception'}: '
      '${text.split('\n').first}',
    );
  }
  if (problems.isNotEmpty) {
    fail('${context ?? 'Frame'} reported:\n  ${problems.join('\n  ')}');
  }
}

/// Pumps the app built by [build] under every variant of [variants] and
/// fails on any `RenderFlex` overflow or other framework exception.
///
/// [verify] runs after each variant has settled (e.g. accessibility checks).
Future<void> pumpMatrix(
  WidgetTester tester,
  Widget Function(HarnessVariant variant) build, {
  List<HarnessVariant>? variants,
  Future<void> Function(HarnessVariant variant)? verify,
}) async {
  for (final variant in variants ?? harnessMatrix()) {
    applyVariantView(tester, variant);
    await tester.pumpWidget(
      KeyedSubtree(key: ValueKey(variant.label), child: build(variant)),
    );
    await tester.pumpAndSettle();
    expectNoFrameworkExceptions(tester, context: variant.label);
    if (verify != null) await verify(variant);
  }
}
