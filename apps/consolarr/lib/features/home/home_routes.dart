// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/home/home_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:material_ui/material_ui.dart';

/// Route of the home screen.
const homeRoute = '/';

/// Home tab: always offered.
final homeDestination = AppDestination(
  id: 'home',
  route: homeRoute,
  icon: Icons.home_outlined,
  selectedIcon: Icons.home,
  label: (l10n) => l10n.navHome,
  builder: (context, state) => const HomeScreen(),
);
