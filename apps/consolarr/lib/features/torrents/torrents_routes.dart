// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/application/torrent_client_registry.dart';
import 'package:consolarr/features/torrents/data/torrents_prefs.dart';
import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the torrent list.
const torrentsRoute = '/torrents';

/// Torrents tab: offered once a torrent client server of any kind exists. The
/// kinds, and the kinds the switcher lists, are exactly the registered clients
/// ([torrentClientFactories]); a new client needs no change here.
final torrentsDestination = AppDestination(
  id: TorrentsPrefs.destinationId,
  route: torrentsRoute,
  icon: Icons.download_outlined,
  selectedIcon: Icons.download,
  label: (l10n) => l10n.navTorrents,
  kinds: torrentClientFactories.keys.toSet(),
  screen: ScreenName.torrentList,
  // Every torrent client's servers are listed together in the switcher.
  switcherKinds: torrentClientFactories.keys.toSet(),
  builder: (context, state) => const TorrentListScreen(),
);
