// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/dashboard/application/dashboard_source.dart';
import 'package:consolarr/features/dashboard/data/arr_sources.dart';
import 'package:consolarr/features/dashboard/data/torrent_source.dart';
import 'package:core/core.dart';

/// Dashboard sources per [ServiceKind]; a new service is one line here.
final Map<ServiceKind, DashboardSource> dashboardSources = {
  ServiceKind.sonarr: sonarrDashboardSource,
  ServiceKind.radarr: radarrDashboardSource,
  ServiceKind.qbittorrent: torrentDashboardSource(ServiceKind.qbittorrent),
  ServiceKind.transmission: torrentDashboardSource(ServiceKind.transmission),
  ServiceKind.deluge: torrentDashboardSource(ServiceKind.deluge),
};
