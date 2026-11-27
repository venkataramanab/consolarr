// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/about/app_info.dart';
import 'package:consolarr/features/about/source_link.dart';
import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// About (SET-13): version, open-source licenses, source link, the licence
/// and independence notice, and the privacy statement listing every host the
/// app can contact that is not the user's own.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  String? _message;

  Future<void> _openSource() async {
    final l10n = context.l10n;
    final opened = await ref
        .read(externalActionsProvider)
        .openHttps(sourceRepositoryUri);
    if (mounted)
      setState(() => _message = opened ? null : l10n.aboutOpenFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SettingsPage(
      title: l10n.aboutTitle,
      screen: ScreenName.about,
      children: [
        Text(l10n.aboutLicense, style: theme.textTheme.bodyLarge),
        const SizedBox(height: ConsolarrSpacing.md),
        Text(l10n.aboutIndependence, style: theme.textTheme.bodyMedium),
        const SizedBox(height: ConsolarrSpacing.section),
        SettingsSection(
          title: l10n.aboutTitle,
          children: [
            SettingsRow(
              title: l10n.aboutVersionTitle,
              icon: Icons.tag,
              value: l10n.aboutVersionValue(appVersion, appBuild),
            ),
            SettingsRow(
              title: l10n.aboutLicensesRow,
              icon: Icons.description_outlined,
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: '$appVersion+$appBuild',
              ),
            ),
            SettingsRow(
              title: l10n.aboutSourceRow,
              subtitle: l10n.aboutSourceRowSubtitle,
              icon: Icons.code,
              trailing: const ExcludeSemantics(child: Icon(Icons.open_in_new)),
              onTap: _openSource,
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.md),
            child: Semantics(
              liveRegion: true,
              child: Text(_message!, style: theme.textTheme.bodyMedium),
            ),
          ),
        Semantics(
          header: true,
          child: Text(
            l10n.aboutPrivacyHeading,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        Text(l10n.aboutPrivacyBody, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
