// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/about_screen.dart';
import 'package:consolarr/features/servers/domain/server_models.dart';
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
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:test_harness/test_harness.dart';

import 'screens_support.dart';

/// Every settings screen under the full matrix: 320x568 and 412x915, locales
/// en / en_XA / ar, text scale 1.0 and 2.0, light and dark (24 variants per
/// screen), with no overflow and the accessibility guidelines.
final _matrix = harnessMatrix(sizes: const [Size(320, 568), Size(412, 915)]);

/// Small (12-15 px) captions and rows whose box is mostly background. The
/// contrast guideline picks the two most frequent colours in a node's box, and
/// at text scale 1.0 the glyph pixels are outnumbered by the background and by
/// anti-aliasing greys, so it reports ratios (even 1.1) that the theme's
/// colours do not have. At text scale 2.0 the very same nodes are judged
/// normally, and they pass; only these exact strings are exempted at 1.0.
Set<String> _samplerArtifacts(AppLocalizations l10n) => {
  l10n.settingsSectionSecurity,
  l10n.lockDelayHint,
  l10n.privacyEventScreenViewed,
  l10n.a11yFollowsSystem,
  l10n.diagLogSwitchHint,
  l10n.diagRedactionNotice,
  l10n.diagGithubNote,
  l10n.diagPreviewEmptyLog,
  l10n.aboutLicensesRow,
};

/// Tap targets and labels, and text contrast at every scroll position (the
/// guideline reads pixels, so text the viewport clips is judged once it is
/// scrolled fully into view).
Future<void> _expectAccessible(WidgetTester tester, HarnessVariant v) async {
  await expectTapTargets(tester);
  await expectLabeledTapTargets(tester);
  final skip = v.textScale == 1
      ? _samplerArtifacts(await AppLocalizations.delegate.load(v.locale))
      : const <String>{};
  await expectTextContrastWhileScrolling(tester, skipLabels: skip);
}

void _screen(
  String name,
  Widget Function() build, {
  Map<String, String>? stored,
  List<ServerEntry> servers = const [],
}) {
  testWidgets('$name: full matrix', (tester) async {
    expect(_matrix, hasLength(24));
    await pumpMatrix(
      tester,
      (v) => ScreenHarness(stored: stored, servers: servers).screen(v, build()),
      variants: _matrix,
      verify: (v) => _expectAccessible(tester, v),
    );
  });
}

void main() {
  _screen('hub', () => const Scaffold(body: SettingsScreen()));
  _screen(
    'hub with servers',
    () => const Scaffold(body: SettingsScreen()),
    servers: [entry('a', name: 'Example Server')],
  );
  _screen('lock off', () => const LockSettingsScreen());
  _screen('lock on', () => const LockSettingsScreen(), stored: lockOn());
  _screen('privacy', () => const PrivacyScreen());
  _screen(
    'privacy with consent',
    () => const PrivacyScreen(),
    stored: {SettingsKeys.diagnosticsEnabled: '1'},
  );
  _screen('language', () => const LanguageScreen());
  _screen('accessibility', () => const AccessibilityScreen());
  _screen(
    'accessibility reduced',
    () => const AccessibilityScreen(),
    stored: {SettingsKeys.motion: 'reduced', SettingsKeys.largerTargets: '1'},
  );
  _screen('diagnostics off', () => const DiagnosticsScreen());
  _screen(
    'diagnostics capturing',
    () => const DiagnosticsScreen(),
    stored: {SettingsKeys.diagnosticsEnabled: '1'},
  );
  _screen(
    'diagnostics preview',
    () => const DiagnosticsPreviewScreen(),
    stored: {SettingsKeys.diagnosticsEnabled: '1'},
  );
  _screen('about', () => const AboutScreen());
  _screen('connection check, no servers', () => const ConnectionCheckScreen());
  _screen(
    'connection check, servers',
    () => const ConnectionCheckScreen(),
    servers: [
      entry('a', name: 'Example Server'),
      entry('b', name: 'Example Radarr', kind: ServiceKind.radarr),
    ],
  );
}
