// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/language_names.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:consolarr/features/settings/settings_paths.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// The settings hub (SET-01): grouped rows that lead to every area.
/// (Notifications is Later and has no row.)
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final consent = ref.watch(consentProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final languageValue = settings.localeTag == null
        ? l10n.languageFollowSystem
        : languageName(settings.localeTag!);

    final sections = <Widget>[
      SettingsSection(
        title: l10n.settingsSectionServers,
        children: [
          SettingsRow(
            title: l10n.settingsServersRow,
            subtitle: l10n.settingsServersRowSubtitle,
            icon: Icons.dns_outlined,
            onTap: () => context.go(SettingsPaths.servers),
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionDisplay,
        children: [
          ChoiceSheetRow<ThemeMode>(
            title: l10n.settingsThemeTitle,
            icon: Icons.palette_outlined,
            closeLabel: l10n.settingsClose,
            options: [
              ChoiceOption(
                value: ThemeMode.dark,
                label: l10n.settingsThemeDark,
              ),
              ChoiceOption(
                value: ThemeMode.light,
                label: l10n.settingsThemeLight,
              ),
              ChoiceOption(
                value: ThemeMode.system,
                label: l10n.settingsThemeSystem,
              ),
            ],
            selected: settings.themeMode,
            onSelected: notifier.setThemeMode,
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionSecurity,
        children: [
          SettingsRow(
            title: l10n.settingsLockRow,
            icon: Icons.lock_outline,
            value: settings.lockEnabled
                ? l10n.settingsLockOn
                : l10n.settingsLockOff,
            onTap: () => context.push(SettingsPaths.lock),
          ),
          SwitchRow(
            title: l10n.settingsBlockScreenshotsTitle,
            subtitle: l10n.settingsBlockScreenshotsSubtitle,
            icon: Icons.screenshot_outlined,
            value: settings.blockScreenshots || settings.lockEnabled,
            // The lock needs the secure window, so the switch is fixed on.
            onChanged: settings.lockEnabled
                ? null
                : notifier.setBlockScreenshots,
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionPrivacy,
        children: [
          SettingsRow(
            title: l10n.settingsPrivacyRow,
            subtitle: (consent.analytics || consent.crashReports)
                ? l10n.settingsPrivacyRowSubtitleOn
                : l10n.settingsPrivacyRowSubtitle,
            icon: Icons.privacy_tip_outlined,
            onTap: () => context.push(SettingsPaths.privacy),
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionLanguage,
        children: [
          SettingsRow(
            title: l10n.settingsLanguageRow,
            icon: Icons.language,
            value: languageValue,
            onTap: () => context.push(SettingsPaths.language),
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionAccessibility,
        children: [
          SettingsRow(
            title: l10n.settingsAccessibilityRow,
            subtitle: l10n.settingsAccessibilityRowSubtitle,
            icon: Icons.accessibility_new,
            onTap: () => context.push(SettingsPaths.accessibility),
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionDiagnostics,
        children: [
          SettingsRow(
            title: l10n.settingsDiagnosticsRow,
            subtitle: l10n.settingsDiagnosticsRowSubtitle,
            icon: Icons.bug_report_outlined,
            onTap: () => context.push(SettingsPaths.diagnostics),
          ),
        ],
      ),
      SettingsSection(
        title: l10n.settingsSectionAbout,
        children: [
          SettingsRow(
            title: l10n.settingsAboutRow,
            icon: Icons.info_outline,
            onTap: () => context.push(SettingsPaths.about),
          ),
        ],
      ),
    ];

    return ScreenTracker(
      screen: ScreenName.settings,
      child: FloatingTopBarScaffold(
        title: l10n.settingsTitle,
        bodyBuilder: (context, padding) => ListView(
          padding: padding,
          children: [
            // Clear of the bar's fade edge, so the first heading keeps its
            // contrast.
            const SizedBox(height: ConsolarrSpacing.lg),
            for (var i = 0; i < sections.length; i++)
              StagedReveal(
                revealKey: 'settings.hub',
                order: i,
                child: sections[i],
              ),
          ],
        ),
      ),
    );
  }
}
