// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:material_ui/material_ui.dart';

/// Placeholder until the calendar tab is built.
final SonarrTab calendarTab = SonarrTab(
  id: 'calendar',
  icon: Icons.calendar_month_outlined,
  label: (l10n) => l10n.sonarrTitle,
  body: (context, padding) => const SizedBox.shrink(),
);
