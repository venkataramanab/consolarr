// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/src/router.dart';
import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';

/// Placeholder home screen (no product features yet).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            tooltip: l10n.homeAboutTooltip,
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push(AppRoutes.about),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(ConsolarrSpacing.gutter),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ExcludeSemantics(
                        child: Icon(Icons.dns_outlined, size: 64),
                      ),
                      const SizedBox(height: ConsolarrSpacing.lg),
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.homeEmptyHeading,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: ConsolarrSpacing.sm),
                      Text(
                        l10n.homeEmptyBody,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: ConsolarrSpacing.lg),
                      Text(
                        l10n.homeServerCount(0),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
