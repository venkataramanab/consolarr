// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/settings/application/settings_providers.dart';
import 'package:consolarr/features/settings/domain/language_names.dart';
import 'package:consolarr/features/settings/presentation/settings_page.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// App language (SET-08): follow the system or pick one of the shipped
/// languages, each written in itself. Right-to-left languages mirror the
/// layout through the app's locale.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tag = ref.watch(settingsProvider.select((s) => s.localeTag));
    final roles = context.roles;
    final theme = Theme.of(context);

    Widget option({required String label, required String? value}) {
      final selected = tag == value;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: () => ref.read(settingsProvider.notifier).setLocaleTag(value),
        child: InkWell(
          onTap: () => ref.read(settingsProvider.notifier).setLocaleTag(value),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: TouchTargets.of(context).minimum,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ConsolarrSpacing.lg,
                vertical: ConsolarrSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodyLarge),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? roles.accent : roles.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SettingsPage(
      title: l10n.languageTitle,
      screen: ScreenName.settingsLanguage,
      children: [
        SettingsSection(
          title: l10n.languageTitle,
          footer: l10n.languageHint,
          children: [
            option(label: l10n.languageFollowSystem, value: null),
            for (final locale in shippedLanguages())
              // The endonym is shown in its own language and direction, and a
              // screen reader pronounces it in that language.
              Semantics(
                localeForSubtree: Locale(locale.languageCode),
                child: Directionality(
                  textDirection: locale.languageCode == 'ar'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: option(
                    label: languageName(locale.languageCode),
                    value: locale.languageCode,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
