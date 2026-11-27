// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:l10n/l10n.dart';

/// Licence and independence notice.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
          children: [
            Text(l10n.aboutLicense, style: theme.textTheme.bodyLarge),
            const SizedBox(height: ConsolarrSpacing.md),
            Text(l10n.aboutIndependence, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
