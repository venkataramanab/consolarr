// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/sonarr_library_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the series library.
const sonarrRoute = '/sonarr';

/// Sonarr tab: offered once a Sonarr server exists.
final sonarrDestination = AppDestination(
  id: 'sonarr',
  route: sonarrRoute,
  icon: Icons.tv_outlined,
  selectedIcon: Icons.tv,
  label: (l10n) => l10n.navSonarr,
  kinds: const {ServiceKind.sonarr},
  screen: ScreenName.sonarrLibrary,
  switcherKind: ServiceKind.sonarr,
  builder: (context, state) => const SonarrLibraryScreen(),
);
