// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/servers/domain/server_models.dart';
import 'package:consolarr/features/shell/application/shell_providers.dart';
import 'package:consolarr/features/shell/presentation/floating_top_bar_scaffold.dart';
import 'package:consolarr/src/router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Home: the first-run setup prompt, or the list of configured services.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final servers = ref.watch(uiServersProvider).value ?? const <ServerEntry>[];
    return FloatingTopBarScaffold(
      title: l10n.homeTitle,
      actions: [
        IconButton(
          tooltip: l10n.homeAboutTooltip,
          icon: const Icon(Icons.info_outline),
          onPressed: () => context.push(AppRoutes.about),
        ),
      ],
      bodyBuilder: (context, padding) => CustomScrollView(
        slivers: [
          if (servers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: padding,
                child: Center(
                  child: EmptyState(
                    icon: Icons.dns_outlined,
                    headline: l10n.homeEmptyHeading,
                    message: l10n.homeEmptyBody,
                    actionLabel: l10n.homeSetupCta,
                    onAction: () => context.push(AppRoutes.onboarding),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: padding,
              sliver: SliverList.list(
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.homeServicesHeading,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: ConsolarrSpacing.sm),
                  Text(
                    l10n.homeServerCount(servers.length),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: ConsolarrSpacing.md),
                  for (final kind in ServiceKind.values.where(
                    (k) => servers.any((s) => s.profile.kind == k),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: ConsolarrSpacing.sm,
                      ),
                      child: Card(
                        child: ListTile(
                          minTileHeight: ConsolarrSpacing.minTapTarget,
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(
                            servers
                                .where((s) => s.profile.kind == kind)
                                .map((s) => s.profile.name)
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
