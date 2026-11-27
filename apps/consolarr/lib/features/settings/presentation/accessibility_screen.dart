// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Accessibility (SET-12): reduce-motion override, larger touch targets and
/// high contrast. Text size and the screen reader come from the device.
class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return SettingsPage(
      title: l10n.a11yTitle,
      screen: ScreenName.settingsAccessibility,
      children: [
        SettingsSection(
          title: l10n.a11yTitle,
          footer: l10n.a11yFollowsSystem,
          children: [
            SwitchRow(
              title: l10n.a11yMotionTitle,
              subtitle: l10n.a11yMotionSubtitle,
              icon: Icons.animation,
              value: s.motion == MotionPreference.reduced,
              onChanged: (v) => n.setMotion(
                v ? MotionPreference.reduced : MotionPreference.system,
              ),
            ),
            SwitchRow(
              title: l10n.a11yTargetsTitle,
              subtitle: l10n.a11yTargetsSubtitle,
              icon: Icons.touch_app_outlined,
              value: s.largerTargets,
              onChanged: n.setLargerTargets,
            ),
            SwitchRow(
              title: l10n.a11yContrastTitle,
              subtitle: l10n.a11yContrastSubtitle,
              icon: Icons.contrast,
              value: s.highContrast,
              onChanged: n.setHighContrast,
            ),
          ],
        ),
      ],
    );
  }
}
