// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:consolarr/features/sonarr/presentation/queue/queue_body.dart';
import 'package:consolarr/features/sonarr/presentation/sonarr_tab.dart';
import 'package:material_ui/material_ui.dart';

/// The queue tab (SON-14, SON-15): active downloads with removal.
final SonarrTab queueTab = SonarrTab(
  id: 'queue',
  icon: Icons.download_outlined,
  label: (l10n) => l10n.sonarrTabQueue,
  body: (context, padding) => QueueBody(padding: padding),
);
