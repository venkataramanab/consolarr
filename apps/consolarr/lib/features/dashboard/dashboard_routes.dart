// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/presentation/dashboard_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the dashboard, the home screen.
const homeRoute = '/';

/// Dashboard tab (the first branch): always offered. Its id stays `home`.
final homeDestination = AppDestination(
  id: 'home',
  route: homeRoute,
  icon: Icons.dashboard_outlined,
  selectedIcon: Icons.dashboard,
  label: (l10n) => l10n.navDashboard,
  screen: ScreenName.dashboard,
  builder: (context, state) => const DashboardScreen(),
);
