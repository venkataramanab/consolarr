// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/presentation/accessibility_screen.dart';
import 'package:consolarr/features/settings/presentation/connection_check_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_preview_screen.dart';
import 'package:consolarr/features/settings/presentation/diagnostics_screen.dart';
import 'package:consolarr/features/settings/presentation/language_screen.dart';
import 'package:consolarr/features/settings/presentation/lock_settings_screen.dart';
import 'package:consolarr/features/settings/presentation/privacy_screen.dart';
import 'package:consolarr/features/settings/presentation/settings_screen.dart';
import 'package:consolarr/features/settings/settings_paths.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Settings tab: always offered. The sub-screens are child routes inside the
/// shell (the bar stays visible).
final settingsDestination = AppDestination(
  id: 'settings',
  route: SettingsPaths.hub,
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
  label: (l10n) => l10n.navSettings,
  screen: ScreenName.settings,
  builder: (context, state) => const SettingsScreen(),
  children: [
    GoRoute(
      path: 'lock',
      builder: (context, state) => const LockSettingsScreen(),
    ),
    GoRoute(
      path: 'privacy',
      builder: (context, state) => const PrivacyScreen(),
    ),
    GoRoute(
      path: 'language',
      builder: (context, state) => const LanguageScreen(),
    ),
    GoRoute(
      path: 'accessibility',
      builder: (context, state) => const AccessibilityScreen(),
    ),
    GoRoute(
      path: 'diagnostics',
      builder: (context, state) => const DiagnosticsScreen(),
      routes: [
        GoRoute(
          path: 'preview',
          builder: (context, state) => const DiagnosticsPreviewScreen(),
        ),
        GoRoute(
          path: 'check',
          builder: (context, state) => const ConnectionCheckScreen(),
        ),
      ],
    ),
  ],
);
