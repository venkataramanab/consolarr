// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/privacy_payload.dart';
import 'package:consolarr/features/settings/presentation/consent_explainer.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Privacy and consent (SET-03): two independent switches, both off by
/// default, with the exact payload described.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final consent = ref.watch(consentProvider);
    final available = ref.watch(telemetryAvailableProvider);
    return SettingsPage(
      title: l10n.privacyTitle,
      screen: ScreenName.settingsPrivacy,
      children: [
        ConsentExplainer(
          state: consent,
          onChanged: (purpose, on) =>
              ref.read(consentProvider.notifier).set(purpose, enabled: on),
        ),
        Semantics(
          header: true,
          child: Text(
            l10n.privacyListHeading,
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: ConsolarrSpacing.sm),
        for (final describe in [
          ...privacyPayloadItems.values,
          (AppLocalizations l10n) => l10n.privacyEventOther,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: ConsolarrSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(child: Icon(Icons.circle, size: 8)),
                const SizedBox(width: ConsolarrSpacing.md),
                Expanded(
                  child: Text(
                    describe(l10n),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: ConsolarrSpacing.md),
        Text(l10n.privacyWithdrawHint, style: theme.textTheme.bodyMedium),
        if (!available) ...[
          const SizedBox(height: ConsolarrSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Icon(Icons.info_outline)),
              const SizedBox(width: ConsolarrSpacing.sm),
              Expanded(
                child: Text(
                  l10n.privacyNoServiceNote,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
