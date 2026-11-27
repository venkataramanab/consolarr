// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/radarr/presentation/radarr_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the Radarr area.
const radarrRoute = '/radarr';

/// Radarr tab: offered once a Radarr server exists.
///
/// Detail, add and search are full-screen flows pushed from
/// `presentation/navigation.dart` until `AppDestination.children` exists on
/// `main`.
final radarrDestination = AppDestination(
  id: 'radarr',
  route: radarrRoute,
  icon: Icons.movie_outlined,
  selectedIcon: Icons.movie,
  label: (l10n) => l10n.navRadarr,
  kinds: const {ServiceKind.radarr},
  screen: ScreenName.radarrLibrary,
  switcherKind: ServiceKind.radarr,
  builder: (context, state) => const RadarrScreen(),
);
