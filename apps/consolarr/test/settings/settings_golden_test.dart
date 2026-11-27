// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/settings/application/diagnostics_providers.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/app_settings.dart';
import 'package:consolarr/features/settings/presentation/accessibility_screen.dart';
import 'package:consolarr/features/settings/presentation/connection_check_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_preview_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_screen.dart';
import 'package:consolarr/features/settings/presentation/language_screen.dart';
import 'package:consolarr/features/settings/presentation/lock_settings_screen.dart';
import 'package:consolarr/features/settings/presentation/privacy_screen.dart';
import 'package:consolarr/features/settings/presentation/settings_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

/// name -> (harness variant, high contrast)
const _variants = {
  'dark_en_360x800': (
    HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    ),
    false,
  ),
  'light_ar_320x568_x2': (
    HarnessVariant(
      size: Size(320, 568),
      textScale: 2,
      locale: Locale('ar'),
      brightness: Brightness.light,
    ),
    false,
  ),
  'dark_enXA_412x915': (
    HarnessVariant(
      size: Size(412, 915),
      textScale: 1,
      locale: Locale('en', 'XA'),
      brightness: Brightness.dark,
    ),
    false,
  ),
  'light_hc_en_360x800': (
    HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.light,
    ),
    true,
  ),
};

class _Screen {
  const _Screen(this.build, {this.stored});

  final Widget Function() build;
  final Map<String, String>? stored;
}

final _screens = <String, _Screen>{
  'hub': _Screen(() => const Scaffold(body: SettingsScreen())),
  'lock_on': _Screen(() => const LockSettingsScreen(), stored: lockOn()),
  'privacy': _Screen(() => const PrivacyScreen()),
  'language': _Screen(() => const LanguageScreen()),
  'accessibility': _Screen(
    () => const AccessibilityScreen(),
    stored: {SettingsKeys.motion: 'reduced', SettingsKeys.largerTargets: '1'},
  ),
  'diagnostics_capturing': _Screen(
    () => const DiagnosticsScreen(),
    stored: {SettingsKeys.diagnosticsEnabled: '1'},
  ),
  'diagnostics_off': _Screen(() => const DiagnosticsScreen()),
  'preview': _Screen(
    () => const DiagnosticsPreviewScreen(),
    stored: {SettingsKeys.diagnosticsEnabled: '1'},
  ),
  'about': _Screen(() => const AboutScreen()),
};

void main() {
  _screens.forEach((name, screen) {
    _variants.forEach((vName, pair) {
      testWidgets('golden: $name $vName', (tester) async {
        final (v, hc) = pair;
        final h = ScreenHarness(stored: screen.stored);
        applyVariantView(tester, v);
        final child = screen.build();
        await tester.pumpWidget(
          h.screen(
            v,
            hc
                ? Theme(
                    data: v.brightness == Brightness.dark
                        ? ConsolarrTheme.dark(highContrast: true)
                        : ConsolarrTheme.light(highContrast: true),
                    child: child,
                  )
                : child,
          ),
        );
        await tester.pumpAndSettle();
        if (name == 'diagnostics_capturing' || name == 'preview') {
          final c = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
          );
          final log = c.read(diagnosticsLogProvider);
          log.add(LogLevel.error, 'refresh failed (timeout)');
          log.add(LogLevel.warning, 'retry 2 of 3');
          log.add(LogLevel.info, 'server list loaded: 3 servers');
          c.invalidate(diagnosticsBundleProvider);
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_${name}_$vName.png'),
        );
      });
    });
  });

  testWidgets('golden: connection check failed', (tester) async {
    const v = HarnessVariant(
      size: Size(360, 800),
      textScale: 1,
      locale: Locale('en'),
      brightness: Brightness.dark,
    );
    final h = ScreenHarness(servers: [entry('a', name: 'Example Server')]);
    h.ui.tester.outcomes
      ..clear()
      ..add(const ConnectionTestFailure(AppError(ErrorCategory.tlsExpired)));
    applyVariantView(tester, v);
    await tester.pumpWidget(h.screen(v, const ConnectionCheckScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run check'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_connection_check_failed_dark_en.png'),
    );
  });
}
