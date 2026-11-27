// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:consolarr/features/sonarr/presentation/wanted/wanted_body.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The missing tab (SON-20): wanted, missing and upcoming episodes.
final SonarrTab wantedTab = SonarrTab(
  id: 'missing',
  icon: Icons.search_off_outlined,
  label: (l10n) => l10n.sonarrTabMissing,
  body: (context, padding) => WantedBody(
    padding: padding,
    onOpenServers: (context) => GoRouter.maybeOf(context)?.go('/servers'),
  ),
);
