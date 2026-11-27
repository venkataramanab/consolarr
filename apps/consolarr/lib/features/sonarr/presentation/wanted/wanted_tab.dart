// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:material_ui/material_ui.dart';

/// Placeholder until the wanted tab is built.
final SonarrTab wantedTab = SonarrTab(
  id: 'wanted',
  icon: Icons.search_off_outlined,
  label: (l10n) => l10n.sonarrTitle,
  body: (context, padding) => const SizedBox.shrink(),
);
