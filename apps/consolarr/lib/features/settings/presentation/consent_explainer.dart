// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// The two independent consent switches with an explanation of exactly what
/// each sends. Reusable: the privacy screen uses it, and onboarding can place
/// it without any dependency on settings state (it gets the state and a
/// callback). Both switches are off until the user turns them on.
///
/// ```dart
/// ConsentExplainer(
///   state: ref.watch(consentProvider),
///   onChanged: (purpose, on) =>
///       ref.read(consentProvider.notifier).set(purpose, enabled: on),
/// )
/// ```
class ConsentExplainer extends StatelessWidget {
  const ConsentExplainer({
    required this.state,
    required this.onChanged,
    super.key,
  });

  final ConsentState state;
  final void Function(ConsentPurpose purpose, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget block({
      required String title,
      required String what,
      required bool value,
      required ConsentPurpose purpose,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: title,
          children: [
            SwitchRow(
              title: title,
              value: value,
              onChanged: (v) => onChanged(purpose, v),
            ),
          ],
          footer: what,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: ConsolarrSpacing.lg),
          child: Text(l10n.privacyIntro, style: theme.textTheme.bodyLarge),
        ),
        block(
          title: l10n.privacyCrashTitle,
          what: l10n.privacyCrashWhat,
          value: state.crashReports,
          purpose: ConsentPurpose.crashReports,
        ),
        block(
          title: l10n.privacyAnalyticsTitle,
          what: l10n.privacyAnalyticsWhat,
          value: state.analytics,
          purpose: ConsentPurpose.analytics,
        ),
      ],
    );
  }
}
