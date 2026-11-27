// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/torrents/presentation/torrent_list_screen.dart';
import 'package:consolarr/src/navigation/app_destination.dart';
import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:observability/observability.dart';

/// Route of the torrent list.
const torrentsRoute = '/torrents';

/// Torrents tab: offered once a torrent client server of any kind exists.
final torrentsDestination = AppDestination(
  id: 'torrents',
  route: torrentsRoute,
  icon: Icons.download_outlined,
  selectedIcon: Icons.download,
  label: (l10n) => l10n.navTorrents,
  kinds: const {
    ServiceKind.qbittorrent,
    ServiceKind.transmission,
    ServiceKind.deluge,
  },
  screen: ScreenName.torrentList,
  // Every torrent client's servers are listed together in the switcher.
  switcherKinds: const {
    ServiceKind.qbittorrent,
    ServiceKind.transmission,
    ServiceKind.deluge,
  },
  builder: (context, state) => const TorrentListScreen(),
);
