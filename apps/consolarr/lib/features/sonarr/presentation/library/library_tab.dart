// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/application/sonarr_providers.dart';
import 'package:consolarr/features/sonarr/presentation/library/library_body.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:consolarr/features/sonarr/sonarr_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The library tab. [onOpenServers] opens the servers screen.
SonarrTab buildLibraryTab({
  required void Function(BuildContext context) onOpenServers,
}) => SonarrTab(
  id: 'library',
  icon: Icons.video_library_outlined,
  label: (l10n) => l10n.sonarrTabLibrary,
  body: (context, padding) =>
      LibraryBody(padding: padding, onOpenServers: onOpenServers),
  actions: (context) => const [_ViewModeButton(), _AddButton()],
);

class _ViewModeButton extends ConsumerWidget {
  const _ViewModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isGrid = ref.watch(viewModeProvider) == LibraryViewMode.grid;
    return IconButton(
      tooltip: isGrid
          ? l10n.sonarrSwitchToListTooltip
          : l10n.sonarrSwitchToGridTooltip,
      icon: Icon(isGrid ? Icons.view_list_outlined : Icons.grid_view),
      onPressed: () => ref
          .read(viewModeProvider.notifier)
          .set(isGrid ? LibraryViewMode.list : LibraryViewMode.grid),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.l10n.sonarrLibraryAddTooltip,
    icon: const Icon(Icons.add),
    onPressed: () => GoRouter.maybeOf(context)?.push(sonarrAddLocation()),
  );
}
